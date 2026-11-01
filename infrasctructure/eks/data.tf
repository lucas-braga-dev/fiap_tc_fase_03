resource "aws_security_group" "data" {
  name_prefix = "${local.name}-data-"
  vpc_id      = module.network.vpc_id
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_eks_cluster.main.vpc_config[0].cluster_security_group_id]
  }
  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_eks_cluster.main.vpc_config[0].cluster_security_group_id]
  }
}
resource "aws_db_subnet_group" "main" {
  name       = local.name
  subnet_ids = module.network.private_subnets
}
resource "aws_db_instance" "service" {
  for_each                    = local.databases
  identifier                  = "${local.name}-${each.key}"
  engine                      = "postgres"
  instance_class              = "db.t3.micro"
  allocated_storage           = 20
  max_allocated_storage       = 50
  storage_encrypted           = true
  db_name                     = each.value
  username                    = "dbadmin"
  manage_master_user_password = true
  publicly_accessible         = false
  db_subnet_group_name        = aws_db_subnet_group.main.name
  vpc_security_group_ids      = [aws_security_group.data.id]
  backup_retention_period     = var.rds_backup_retention_days
  skip_final_snapshot         = true
}
resource "aws_elasticache_subnet_group" "main" {
  name       = local.name
  subnet_ids = module.network.private_subnets
}
resource "aws_elasticache_replication_group" "redis" {
  replication_group_id       = local.name
  description                = "ToggleMaster Redis"
  engine                     = "redis"
  node_type                  = "cache.t3.micro"
  num_cache_clusters         = 1
  port                       = 6379
  subnet_group_name          = aws_elasticache_subnet_group.main.name
  security_group_ids         = [aws_security_group.data.id]
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auto_minor_version_upgrade = true
}
resource "aws_dynamodb_table" "analytics" {
  name         = "ToggleMasterAnalytics-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "event_id"
  attribute {
    name = "event_id"
    type = "S"
  }
  point_in_time_recovery { enabled = true }
  server_side_encryption { enabled = true }
}
resource "aws_sqs_queue" "dlq" {
  name                      = "${local.name}-events-dlq"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
}
resource "aws_sqs_queue" "events" {
  name                       = "${local.name}-events"
  receive_wait_time_seconds  = 20
  visibility_timeout_seconds = 120
  sqs_managed_sse_enabled    = true
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 5
  })
}
resource "aws_ecr_repository" "service" {
  for_each             = local.services
  name                 = "togglemaster/${each.key}"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = true }
}
resource "aws_ecr_lifecycle_policy" "service" {
  for_each   = local.services
  repository = aws_ecr_repository.service[each.key].name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Remove apenas imagens sem tag"
      selection    = { tagStatus = "untagged", countType = "sinceImagePushed", countUnit = "days", countNumber = 7 }
      action       = { type = "expire" }
    }]
  })
}
