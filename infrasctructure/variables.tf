variable "aws_region" {
    type        = string
    default     = "sa-east-1"
}

variable "environment" {
    type        = string
    default     = "dev"
}

variable "db_password" {
    type        = string
    sensitive   = true
    description = "senha master do RDS DB"
}