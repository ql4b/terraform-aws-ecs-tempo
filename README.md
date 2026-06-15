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
  source  = "ql4b/ecs-tempo/aws"
  version = "~> 1.0"

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
  source  = "ql4b/ecs-tempo/aws"
  version = "~> 1.0"

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
  source  = "ql4b/ecs-tempo/aws"
  version = "~> 1.0"

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
  source  = "ql4b/ecs-tempo/aws"
  version = "~> 1.0"

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

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.3 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_container"></a> [container](#module\_container) | cloudposse/ecs-container-definition/aws | 0.61.2 |
| <a name="module_ecr"></a> [ecr](#module\_ecr) | cloudposse/ecr/aws | 1.0.0 |
| <a name="module_storage"></a> [storage](#module\_storage) | cloudposse/s3-bucket/aws | 4.10.0 |
| <a name="module_this"></a> [this](#module\_this) | cloudposse/label/null | 0.25.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_log_group.tempo](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_ecs_service.tempo](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service) | resource |
| [aws_ecs_task_definition.tempo](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) | resource |
| [aws_iam_role.ecs_task_execution_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.task](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.ecs_task_execution_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_security_group_rule.tempo_http](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_security_group_rule.tempo_otlp_grpc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_security_group_rule.tempo_otlp_http](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_service_discovery_private_dns_namespace.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/service_discovery_private_dns_namespace) | resource |
| [aws_service_discovery_service.tempo](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/service_discovery_service) | resource |
| [aws_ecr_image.backend](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ecr_image) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [aws_vpc.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/vpc) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_additional_tag_map"></a> [additional\_tag\_map](#input\_additional\_tag\_map) | Additional key-value pairs to add to each map in `tags_as_list_of_maps`. Not added to `tags` or `id`.<br/>This is for some rare cases where resources want additional configuration of tags<br/>and therefore take a list of maps with tag key, value, and additional configuration. | `map(string)` | `{}` | no |
| <a name="input_assign_public_ip"></a> [assign\_public\_ip](#input\_assign\_public\_ip) | Assign public IP to ECS tasks (required if no NAT Gateway) | `bool` | `true` | no |
| <a name="input_attributes"></a> [attributes](#input\_attributes) | ID element. Additional attributes (e.g. `workers` or `cluster`) to add to `id`,<br/>in the order they appear in the list. New attributes are appended to the<br/>end of the list. The elements of the list are joined by the `delimiter`<br/>and treated as a single ID element. | `list(string)` | `[]` | no |
| <a name="input_block_retention_hours"></a> [block\_retention\_hours](#input\_block\_retention\_hours) | Trace block retention in hours (default: 2160 = 90 days) | `number` | `2160` | no |
| <a name="input_bootstrap"></a> [bootstrap](#input\_bootstrap) | Set to true on first deploy before pushing an image to ECR | `bool` | `false` | no |
| <a name="input_capacity_provider"></a> [capacity\_provider](#input\_capacity\_provider) | ECS capacity provider: FARGATE or FARGATE\_SPOT (70% cost savings) | `string` | `"FARGATE_SPOT"` | no |
| <a name="input_container_image"></a> [container\_image](#input\_container\_image) | Tempo container image. Use default for standard deployment, or point to a custom ECR image | `string` | `"grafana/tempo:2.10.5"` | no |
| <a name="input_context"></a> [context](#input\_context) | Single object for setting entire context at once.<br/>See description of individual variables for details.<br/>Leave string and numeric variables as `null` to use default value.<br/>Individual variable settings (non-null) override settings in context object,<br/>except for attributes, tags, and additional\_tag\_map, which are merged. | `any` | <pre>{<br/>  "additional_tag_map": {},<br/>  "attributes": [],<br/>  "delimiter": null,<br/>  "descriptor_formats": {},<br/>  "enabled": true,<br/>  "environment": null,<br/>  "id_length_limit": null,<br/>  "label_key_case": null,<br/>  "label_order": [],<br/>  "label_value_case": null,<br/>  "labels_as_tags": [<br/>    "unset"<br/>  ],<br/>  "name": null,<br/>  "namespace": null,<br/>  "regex_replace_chars": null,<br/>  "stage": null,<br/>  "tags": {},<br/>  "tenant": null<br/>}</pre> | no |
| <a name="input_cpu"></a> [cpu](#input\_cpu) | Task CPU units (1024 = 1 vCPU) | `number` | `1024` | no |
| <a name="input_delimiter"></a> [delimiter](#input\_delimiter) | Delimiter to be used between ID elements.<br/>Defaults to `-` (hyphen). Set to `""` to use no delimiter at all. | `string` | `null` | no |
| <a name="input_descriptor_formats"></a> [descriptor\_formats](#input\_descriptor\_formats) | Describe additional descriptors to be output in the `descriptors` output map.<br/>Map of maps. Keys are names of descriptors. Values are maps of the form<br/>`{<br/>   format = string<br/>   labels = list(string)<br/>}`<br/>(Type is `any` so the map values can later be enhanced to provide additional options.)<br/>`format` is a Terraform format string to be passed to the `format()` function.<br/>`labels` is a list of labels, in order, to pass to `format()` function.<br/>Label values will be normalized before being passed to `format()` so they will be<br/>identical to how they appear in `id`.<br/>Default is `{}` (`descriptors` output will be empty). | `any` | `{}` | no |
| <a name="input_ecs_cluster"></a> [ecs\_cluster](#input\_ecs\_cluster) | Name of the ECS cluster to deploy Tempo into | `string` | n/a | yes |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Set to false to prevent the module from creating any resources | `bool` | `null` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | ID element. Usually used for region e.g. 'uw2', 'us-west-2', OR role 'prod', 'staging', 'dev', 'UAT' | `string` | `null` | no |
| <a name="input_id_length_limit"></a> [id\_length\_limit](#input\_id\_length\_limit) | Limit `id` to this many characters (minimum 6).<br/>Set to `0` for unlimited length.<br/>Set to `null` for keep the existing setting, which defaults to `0`.<br/>Does not affect `id_full`. | `number` | `null` | no |
| <a name="input_ingress_cidr_blocks"></a> [ingress\_cidr\_blocks](#input\_ingress\_cidr\_blocks) | CIDR blocks allowed to reach Tempo ports. Defaults to VPC CIDR if empty | `list(string)` | `[]` | no |
| <a name="input_label_key_case"></a> [label\_key\_case](#input\_label\_key\_case) | Controls the letter case of the `tags` keys (label names) for tags generated by this module.<br/>Does not affect keys of tags passed in via the `tags` input.<br/>Possible values: `lower`, `title`, `upper`.<br/>Default value: `title`. | `string` | `null` | no |
| <a name="input_label_order"></a> [label\_order](#input\_label\_order) | The order in which the labels (ID elements) appear in the `id`.<br/>Defaults to ["namespace", "environment", "stage", "name", "attributes"].<br/>You can omit any of the 6 labels ("tenant" is the 6th), but at least one must be present. | `list(string)` | `null` | no |
| <a name="input_label_value_case"></a> [label\_value\_case](#input\_label\_value\_case) | Controls the letter case of ID elements (labels) as included in `id`,<br/>set as tag values, and output by this module individually.<br/>Does not affect values of tags passed in via the `tags` input.<br/>Possible values: `lower`, `title`, `upper` and `none` (no transformation).<br/>Set this to `title` and set `delimiter` to `""` to yield Pascal Case IDs.<br/>Default value: `lower`. | `string` | `null` | no |
| <a name="input_labels_as_tags"></a> [labels\_as\_tags](#input\_labels\_as\_tags) | Set of labels (ID elements) to include as tags in the `tags` output.<br/>Default is to include all labels.<br/>Tags with empty values will not be included in the `tags` output.<br/>Set to `[]` to suppress all generated tags.<br/>**Notes:**<br/>  The value of the `name` tag, if included, will be the `id`, not the `name`.<br/>  Unlike other `null-label` inputs, the initial setting of `labels_as_tags` cannot be<br/>  changed in later chained modules. Attempts to change it will be silently ignored. | `set(string)` | <pre>[<br/>  "default"<br/>]</pre> | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | CloudWatch log retention in days | `number` | `30` | no |
| <a name="input_memory"></a> [memory](#input\_memory) | Task memory in MB | `number` | `2048` | no |
| <a name="input_name"></a> [name](#input\_name) | ID element. Usually the component or solution name, e.g. 'app' or 'jenkins'.<br/>This is the only ID element not also included as a `tag`.<br/>The "name" tag is set to the full `id` string. There is no tag with the value of the `name` input. | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | ID element. Usually an abbreviation of your organization name, e.g. 'eg' or 'cp', to help ensure generated IDs are globally unique | `string` | `null` | no |
| <a name="input_network"></a> [network](#input\_network) | Network configuration for the Tempo deployment | <pre>object({<br/>    vpc             = string<br/>    security_group  = string<br/>    public_subnets  = list(string)<br/>    private_subnets = list(string)<br/>  })</pre> | n/a | yes |
| <a name="input_regex_replace_chars"></a> [regex\_replace\_chars](#input\_regex\_replace\_chars) | Terraform regular expression (regex) string.<br/>Characters matching the regex will be removed from the ID elements.<br/>If not set, `"/[^a-zA-Z0-9-]/"` is used to remove all characters other than hyphens, letters and digits. | `string` | `null` | no |
| <a name="input_service_discovery_name"></a> [service\_discovery\_name](#input\_service\_discovery\_name) | Service name registered in Cloud Map (resolves as <name>.<namespace>) | `string` | `"tempo"` | no |
| <a name="input_service_discovery_namespace"></a> [service\_discovery\_namespace](#input\_service\_discovery\_namespace) | Private DNS namespace for Cloud Map service discovery | `string` | `"tempo.local"` | no |
| <a name="input_stage"></a> [stage](#input\_stage) | ID element. Usually used to indicate role, e.g. 'prod', 'staging', 'source', 'build', 'test', 'deploy', 'release' | `string` | `null` | no |
| <a name="input_stop_timeout"></a> [stop\_timeout](#input\_stop\_timeout) | Time to wait for container to stop gracefully before SIGKILL (seconds, max 120) | `number` | `120` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags (e.g. `{'BusinessUnit': 'XYZ'}`).<br/>Neither the tag keys nor the tag values will be modified by this module. | `map(string)` | `{}` | no |
| <a name="input_tenant"></a> [tenant](#input\_tenant) | ID element \_(Rarely used, not included by default)\_. A customer identifier, indicating who this instance of a resource is for | `string` | `null` | no |
| <a name="input_use_ecr"></a> [use\_ecr](#input\_use\_ecr) | Create an ECR repository and use custom image builds. Set to false to use container\_image directly | `bool` | `true` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_ecr_repository_url"></a> [ecr\_repository\_url](#output\_ecr\_repository\_url) | ECR repository URL (null if use\_ecr is false) |
| <a name="output_ecs_service"></a> [ecs\_service](#output\_ecs\_service) | ECS service details |
| <a name="output_endpoints"></a> [endpoints](#output\_endpoints) | Tempo service endpoints via Cloud Map DNS |
| <a name="output_log_group"></a> [log\_group](#output\_log\_group) | CloudWatch log group name |
| <a name="output_s3_bucket"></a> [s3\_bucket](#output\_s3\_bucket) | S3 bucket used for trace block storage |
| <a name="output_service_discovery"></a> [service\_discovery](#output\_service\_discovery) | Cloud Map service discovery details |
<!-- END_TF_DOCS -->

## License

MIT
