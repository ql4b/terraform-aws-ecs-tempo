resource "aws_security_group_rule" "tempo_http" {
  type              = "ingress"
  from_port         = 3200
  to_port           = 3200
  protocol          = "tcp"
  cidr_blocks       = local.ingress_cidr_blocks
  security_group_id = var.network.security_group
  description       = "Tempo HTTP API"
}

resource "aws_security_group_rule" "tempo_otlp_grpc" {
  type              = "ingress"
  from_port         = 4317
  to_port           = 4317
  protocol          = "tcp"
  cidr_blocks       = local.ingress_cidr_blocks
  security_group_id = var.network.security_group
  description       = "Tempo OTLP gRPC ingestion"
}

resource "aws_security_group_rule" "tempo_otlp_http" {
  type              = "ingress"
  from_port         = 4318
  to_port           = 4318
  protocol          = "tcp"
  cidr_blocks       = local.ingress_cidr_blocks
  security_group_id = var.network.security_group
  description       = "Tempo OTLP HTTP ingestion"
}
