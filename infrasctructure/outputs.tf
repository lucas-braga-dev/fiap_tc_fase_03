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