variable "aws_region" {
  type    = string
  default = "us-east-2"
}
variable "environment" {
  type    = string
  default = "fase3"
}
variable "admin_cidrs" {
  type = list(string)
  validation {
    condition     = length(var.admin_cidrs) > 0 && alltrue([for cidr in var.admin_cidrs : can(cidrnetmask(cidr)) && cidr != "0.0.0.0/0"])
    error_message = "Informe os CIDRs publicos dos administradores; nao use 0.0.0.0/0."
  }
}
variable "kubernetes_version" {
  type     = string
  default  = null
  nullable = true
}
variable "node_instance_types" {
  type    = list(string)
  default = ["m7i-flex.large"]
}
variable "rds_backup_retention_days" {
  type        = number
  default     = 1
  description = "Retencao dos backups automaticos RDS; um dia para o plano gratuito."
  validation {
    condition     = var.rds_backup_retention_days >= 0 && var.rds_backup_retention_days <= 35 && floor(var.rds_backup_retention_days) == var.rds_backup_retention_days
    error_message = "Use um numero inteiro entre 0 e 35; no plano gratuito, mantenha 1."
  }
}
