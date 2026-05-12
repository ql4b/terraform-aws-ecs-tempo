output "endpoints" {
  value = {
    api       = "${local.sd_fqdn}:3200"
    otlp_grpc = "${local.sd_fqdn}:4317"
    otlp_http = "${local.sd_fqdn}:4318"
  }
  description = "Tempo service endpoints via Cloud Map DNS"
}

output "s3_bucket" {
  value       = module.storage.bucket_id
  description = "S3 bucket used for trace block storage"
}

output "ecr_repository_url" {
  value       = local.use_ecr ? module.ecr[0].repository_url : null
  description = "ECR repository URL (null if use_ecr is false)"
}

output "ecs_service" {
  value = {
    name            = aws_ecs_service.tempo.name
    id              = aws_ecs_service.tempo.id
    task_definition = aws_ecs_service.tempo.task_definition
    desired_count   = aws_ecs_service.tempo.desired_count
  }
  description = "ECS service details"
}

output "log_group" {
  value       = aws_cloudwatch_log_group.tempo.name
  description = "CloudWatch log group name"
}

output "service_discovery" {
  value = {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id
    service_arn  = aws_service_discovery_service.tempo.arn
    fqdn         = local.sd_fqdn
  }
  description = "Cloud Map service discovery details"
}
