variable "aws_region" {
    type        = string
    default     = "us-east-2"
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

variable "ami_id" {
  type        = string
  description = "ID da AMI do Ubuntu na região us-east-2"
  default     = "ami-052b3645c2c811821" 
}