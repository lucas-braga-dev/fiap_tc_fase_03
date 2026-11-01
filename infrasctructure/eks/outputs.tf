output "cluster_name" { value = aws_eks_cluster.main.name }
output "aws_region" { value = var.aws_region }
output "aws_account_id" { value = data.aws_caller_identity.current.account_id }
output "rds" {
  value = { for key, db in aws_db_instance.service : key => {
    host              = db.address, database = db.db_name, username = db.username,
    master_secret_arn = db.master_user_secret[0].secret_arn
  } }
}
output "redis_url" { value = "rediss://${aws_elasticache_replication_group.redis.primary_endpoint_address}:6379" }
output "sqs_queue_url" { value = aws_sqs_queue.events.url }
output "sqs_dlq_url" { value = aws_sqs_queue.dlq.url }
output "dynamodb_table_name" { value = aws_dynamodb_table.analytics.name }
output "ecr_repositories" { value = { for key, repo in aws_ecr_repository.service : key => repo.repository_url } }
output "workload_roles" { value = { for key, role in aws_iam_role.workload : key => role.arn } }
output "github_ecr_user_name" { value = aws_iam_user.publisher.name }
output "pod_identity_associations" { value = { for key, association in aws_eks_pod_identity_association.workload : key => association.association_id } }
