# terraform-aws-ecs-tempo

Terraform module for deploying [Grafana Tempo](https://grafana.com/oss/tempo/) on AWS ECS Fargate with S3 backend and Cloud Map service discovery.

## Features

- **Grafana Tempo** on ECS Fargate (ARM64) — monolithic mode
- **S3** for trace block storage — no database required
- **Cloud Map** private DNS for zero-config service discovery
- **Fargate Spot** by default — ~70% cost savings
- **OpenTelemetry** native — OTLP gRPC and HTTP ingestion
- **~$10/month** at low-to-moderate trace volumes

## Architecture

```
┌─────────────┐     OTLP       ┌──────────────┐        ┌─────────┐
│  Services   │ ────────────→  │  Tempo (ECS) │ ─────→ │   S3    │
└─────────────┘   :4317/4318   └──────┬───────┘        └─────────┘
                                      │ :3200
                               ┌──────┴───────┐
                               │   Grafana    │
                               └──────────────┘
```

Services export traces via OTLP to Tempo's Cloud Map DNS endpoint. Tempo writes compressed blocks to S3. Grafana queries Tempo's HTTP API on port 3200.

## Usage

```hcl
module "tempo" {
  source = "git::https://github.com/ql4b/terraform-aws-ecs-tempo.git?ref=main"

  namespace  = "myapp"
  name       = "observability"
  attributes = ["tracing"]

  ecs_cluster = aws_ecs_cluster.main.name

  network = {
    vpc             = module.vpc.vpc_id
    security_group  = aws_security_group.main.id
    public_subnets  = module.vpc.public_subnets
    private_subnets = module.vpc.private_subnets
  }

  service_discovery_namespace = "observability.local"
  service_discovery_name      = "tempo"
}
```

Services then export traces to:
```
http://tempo.observability.local:4318/v1/traces
```

## Examples

### Minimal (defaults)

```hcl
module "tempo" {
  source = "git::https://github.com/ql4b/terraform-aws-ecs-tempo.git?ref=main"

  namespace   = "myapp"
  name        = "tempo"
  ecs_cluster = aws_ecs_cluster.main.name

  network = {
    vpc             = module.vpc.vpc_id
    security_group  = aws_security_group.main.id
    public_subnets  = module.vpc.public_subnets
    private_subnets = module.vpc.private_subnets
  }
}
```

### Without ECR (use upstream image directly)

No Docker build required — config is injected at container boot via entrypoint override:

```hcl
module "tempo" {
  source = "git::https://github.com/ql4b/terraform-aws-ecs-tempo.git?ref=main"

  namespace   = "myapp"
  name        = "tempo"
  ecs_cluster = aws_ecs_cluster.main.name
  use_ecr     = false

  network = {
    vpc             = module.vpc.vpc_id
    security_group  = aws_security_group.main.id
    public_subnets  = module.vpc.public_subnets
    private_subnets = module.vpc.private_subnets
  }
}
```

### Custom sizing and retention

```hcl
module "tempo" {
  source = "git::https://github.com/ql4b/terraform-aws-ecs-tempo.git?ref=main"

  namespace   = "prod"
  name        = "tracing"
  ecs_cluster = aws_ecs_cluster.observability.name

  network = {
    vpc             = module.vpc.vpc_id
    security_group  = aws_security_group.main.id
    public_subnets  = module.vpc.public_subnets
    private_subnets = module.vpc.private_subnets
  }

  cpu    = 2048
  memory = 4096

  capacity_provider     = "FARGATE"
  block_retention_hours = 720  # 30 days
  log_retention_days    = 14
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `network` | VPC, security group, and subnet configuration | `object` | — | yes |
| `ecs_cluster` | ECS cluster name to deploy into | `string` | — | yes |
| `service_discovery_namespace` | Private DNS namespace for Cloud Map | `string` | `"tempo.local"` | no |
| `service_discovery_name` | Service name in Cloud Map | `string` | `"tempo"` | no |
| `container_image` | Tempo container image (used when `use_ecr = false`) | `string` | `"grafana/tempo:2.10.5"` | no |
| `capacity_provider` | `FARGATE` or `FARGATE_SPOT` | `string` | `"FARGATE_SPOT"` | no |
| `cpu` | Task CPU units | `number` | `1024` | no |
| `memory` | Task memory in MB | `number` | `2048` | no |
| `stop_timeout` | Graceful shutdown timeout (seconds) | `number` | `120` | no |
| `block_retention_hours` | Trace retention in hours | `number` | `2160` (90 days) | no |
| `log_retention_days` | CloudWatch log retention | `number` | `30` | no |
| `ingress_cidr_blocks` | CIDRs allowed to reach Tempo (defaults to VPC CIDR) | `list(string)` | `[]` | no |
| `assign_public_ip` | Assign public IP (required without NAT Gateway) | `bool` | `true` | no |
| `use_ecr` | Create ECR repo for custom image builds | `bool` | `true` | no |
| `bootstrap` | First deploy before image push | `bool` | `false` | no |

Plus all [cloudposse/label/null](https://github.com/cloudposse/terraform-null-label) context variables (`namespace`, `name`, `attributes`, `tags`, etc.)

## Outputs

| Name | Description |
|------|-------------|
| `endpoints` | Map with `api`, `otlp_grpc`, `otlp_http` endpoints |
| `s3_bucket` | S3 bucket ID for trace storage |
| `ecr_repository_url` | ECR repository URL (null if `use_ecr = false`) |
| `ecs_service` | ECS service name, ID, task definition, desired count |
| `log_group` | CloudWatch log group name |
| `service_discovery` | Cloud Map namespace ID, service ARN, FQDN |

## Deployment

### First deploy (bootstrap)

```bash
terraform apply -var="bootstrap=true"
```

### Build and push image

```bash
# Get ECR URL from output
ECR_URL=$(terraform output -raw ecr_repository_url)

# Login, build, push
aws ecr get-login-password | docker login --username AWS --password-stdin $ECR_URL
docker build -t $ECR_URL:latest .
docker push $ECR_URL:latest
```

### Subsequent deploys

```bash
terraform apply  # bootstrap defaults to false
```

## Client Configuration

### OpenTelemetry SDK (Node.js)

```javascript
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');

const exporter = new OTLPTraceExporter({
  url: 'http://tempo.observability.local:4318/v1/traces',
});
```

### Environment variables

```bash
OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://tempo.observability.local:4318/v1/traces
OTEL_SERVICE_NAME=my-service
```

## Dependencies

- [cloudposse/label/null](https://github.com/cloudposse/terraform-null-label) >= 0.25.0
- [cloudposse/ecr/aws](https://github.com/cloudposse/terraform-aws-ecr) >= 1.0.0
- [cloudposse/s3-bucket/aws](https://github.com/cloudposse/terraform-aws-s3-bucket) >= 4.10.0
- [cloudposse/ecs-container-definition/aws](https://github.com/cloudposse/terraform-aws-ecs-container-definition) >= 0.61.2
- Terraform >= 1.12
- AWS Provider >= 6.14

## License

MIT
