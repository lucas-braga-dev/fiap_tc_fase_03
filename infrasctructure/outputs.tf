output "ec2_public_ip" {
  description = "IP Público da instância EC2 para acesso via SSH / deploy:"
  value       = aws_instance.api_server.public_ip
}

output "rds_endpoint" {
  description = "Endpoint de conexão com o banco de dados:"
  value       = aws_db_instance.postgres.endpoint
}

output "s3_bucket_name" {
  description = "Nome do bucket S3 provisionado:"
  value       = aws_s3_bucket.app_storage.id
}

output "aws_region" {
  description = "Regiao para AWS_REGION no .env da EC2."
  value       = var.aws_region
}

output "sqs_queue_url" {
  description = "URL para AWS_SQS_URL no .env da EC2."
  value       = aws_sqs_queue.evaluation_events.url
}

output "sqs_dlq_url" {
  description = "Fila para inspecionar mensagens que falharam repetidamente."
  value       = aws_sqs_queue.evaluation_events_dlq.url
}

output "dynamodb_table_name" {
  description = "Nome para AWS_DYNAMODB_TABLE no .env da EC2."
  value       = aws_dynamodb_table.analytics.name
}

output "ec2_iam_role_name" {
  description = "IAM Role usada pela aplicacao na EC2."
  value       = aws_iam_role.api_server.name
}
