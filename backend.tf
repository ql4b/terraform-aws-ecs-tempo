# ECS Service
resource "aws_ecs_service" "tempo" {
  name            = module.this.id
  cluster         = local.ecs_cluster
  task_definition = aws_ecs_task_definition.tempo.arn

  desired_count = 1

  force_new_deployment = true

  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100
  propagate_tags                     = "SERVICE"

  service_registries {
    registry_arn = aws_service_discovery_service.tempo.arn
  }

  capacity_provider_strategy {
    capacity_provider = var.capacity_provider
    weight            = 1
    base              = 0
  }

  network_configuration {
    subnets          = slice(local.network.public_subnets, 0, 1)
    security_groups  = [local.network.security_group]
    assign_public_ip = var.assign_public_ip
  }

  tags = module.this.tags
}

# Service Discovery
resource "aws_service_discovery_private_dns_namespace" "main" {
  name = local.sd_namespace
  vpc  = local.network.vpc
}

resource "aws_service_discovery_service" "tempo" {
  name = local.sd_name

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id

    dns_records {
      ttl  = 10
      type = "A"
    }
  }

  health_check_custom_config {}
}

# ECR Repository (optional)
module "ecr" {
  count   = local.use_ecr ? 1 : 0
  source  = "cloudposse/ecr/aws"
  version = "1.0.0"

  name                 = module.this.id
  image_tag_mutability = "MUTABLE"
}

data "aws_ecr_image" "backend" {
  count           = local.use_ecr && !var.bootstrap ? 1 : 0
  repository_name = module.ecr[0].repository_name
  image_tag       = "latest"
}

# Container Definition
module "container" {
  source  = "cloudposse/ecs-container-definition/aws"
  version = "0.61.2"

  container_name  = module.this.id
  container_image = local.container_image
  stop_timeout    = var.stop_timeout

  # When not using ECR, override entrypoint to write config at boot
  entrypoint = local.use_ecr ? null : ["/bin/sh", "-c"]
  command = local.use_ecr ? null : [
    "echo '${replace(local.tempo_config, "'", "'\"'\"'")}' > /tmp/tempo.yml && /tempo -config.file=/tmp/tempo.yml -config.expand-env=true"
  ]

  environment = [
    {
      name  = "S3_BUCKET"
      value = module.storage.bucket_id
    },
    {
      name  = "S3_ENDPOINT"
      value = "s3.${local.region}.amazonaws.com"
    },
    {
      name  = "BLOCK_RETENTION"
      value = "${var.block_retention_hours}h"
    }
  ]

  port_mappings = [
    { containerPort = 3200, protocol = "tcp" },
    { containerPort = 4317, protocol = "tcp" },
    { containerPort = 4318, protocol = "tcp" },
  ]

  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-region        = local.region
      awslogs-group         = aws_cloudwatch_log_group.tempo.name
      awslogs-stream-prefix = "task"
    }
  }
}

# Task Definition
resource "aws_ecs_task_definition" "tempo" {
  family = module.this.id

  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory

  container_definitions = module.container.json_map_encoded_list

  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn      = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  tags = module.this.tags
}

# CloudWatch Logs
resource "aws_cloudwatch_log_group" "tempo" {
  name              = "/aws/ecs/${module.this.id}"
  retention_in_days = var.log_retention_days

  lifecycle {
    prevent_destroy = false
  }
}

# S3 Storage
module "storage" {
  source  = "cloudposse/s3-bucket/aws"
  version = "4.10.0"
  enabled = true

  name = module.this.id

  versioning_enabled  = false
  s3_object_ownership = "BucketOwnerEnforced"

  privileged_principal_actions = [
    "s3:PutObject",
    "s3:GetObject",
    "s3:ListBucket",
    "s3:DeleteObject",
    "s3:GetObjectTagging",
    "s3:PutObjectTagging",
  ]
  privileged_principal_arns = [
    { (aws_iam_role.task.arn) = [""] }
  ]
}
