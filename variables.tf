variable "network" {
  type = object({
    vpc             = string
    security_group  = string
    public_subnets  = list(string)
    private_subnets = list(string)
  })
  description = "Network configuration for the Tempo deployment"
}

variable "ecs_cluster" {
  type        = string
  description = "Name of the ECS cluster to deploy Tempo into"
}

variable "service_discovery_namespace" {
  type        = string
  default     = "tempo.local"
  description = "Private DNS namespace for Cloud Map service discovery"
}

variable "service_discovery_name" {
  type        = string
  default     = "tempo"
  description = "Service name registered in Cloud Map (resolves as <name>.<namespace>)"
}

variable "container_image" {
  type        = string
  default     = "grafana/tempo:2.10.5"
  description = "Tempo container image. Use default for standard deployment, or point to a custom ECR image"
}

variable "capacity_provider" {
  type        = string
  default     = "FARGATE_SPOT"
  description = "ECS capacity provider: FARGATE or FARGATE_SPOT (70% cost savings)"

  validation {
    condition     = contains(["FARGATE", "FARGATE_SPOT"], var.capacity_provider)
    error_message = "capacity_provider must be either FARGATE or FARGATE_SPOT"
  }
}

variable "cpu" {
  type        = number
  default     = 1024
  description = "Task CPU units (1024 = 1 vCPU)"
}

variable "memory" {
  type        = number
  default     = 2048
  description = "Task memory in MB"
}

variable "stop_timeout" {
  type        = number
  default     = 120
  description = "Time to wait for container to stop gracefully before SIGKILL (seconds, max 120)"

  validation {
    condition     = var.stop_timeout >= 0 && var.stop_timeout <= 120
    error_message = "stop_timeout must be between 0 and 120 seconds"
  }
}

variable "block_retention_hours" {
  type        = number
  default     = 2160
  description = "Trace block retention in hours (default: 2160 = 90 days)"
}

variable "log_retention_days" {
  type        = number
  default     = 30
  description = "CloudWatch log retention in days"
}

variable "ingress_cidr_blocks" {
  type        = list(string)
  default     = []
  description = "CIDR blocks allowed to reach Tempo ports. Defaults to VPC CIDR if empty"
}

variable "assign_public_ip" {
  type        = bool
  default     = true
  description = "Assign public IP to ECS tasks (required if no NAT Gateway)"
}

variable "use_ecr" {
  type        = bool
  default     = true
  description = "Create an ECR repository and use custom image builds. Set to false to use container_image directly"
}

variable "bootstrap" {
  type        = bool
  default     = false
  description = "Set to true on first deploy before pushing an image to ECR"
}
