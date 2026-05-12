locals {
  pascal_prefix = replace(title(module.this.id), "/\\W+/", "")
  region        = data.aws_region.current.region
  network       = var.network
  ecs_cluster   = var.ecs_cluster

  ingress_cidr_blocks = length(var.ingress_cidr_blocks) > 0 ? var.ingress_cidr_blocks : [data.aws_vpc.main.cidr_block]

  # Service discovery
  sd_namespace = var.service_discovery_namespace
  sd_name      = var.service_discovery_name
  sd_fqdn      = "${local.sd_name}.${local.sd_namespace}"

  # Container image resolution
  use_ecr       = var.use_ecr
  container_image = local.use_ecr ? local.ecr_image : var.container_image
  ecr_image = local.use_ecr ? (
    var.bootstrap ? "${module.ecr[0].repository_url}:latest" : data.aws_ecr_image.backend[0].image_uri
  ) : ""

  # Tempo config for inline injection (use_ecr = false)
  tempo_config = file("${path.module}/config/tempo.yml")
}

data "aws_region" "current" {}
data "aws_vpc" "main" {
  id = local.network.vpc
}
