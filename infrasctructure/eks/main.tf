terraform {
  required_version = ">= 1.10"
  backend "s3" {}
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.100"
    }
  }
}
provider "aws" {
  region = var.aws_region
  default_tags {
    tags = { Project = "ToggleMaster", Environment = var.environment, ManagedBy = "Terraform" }
  }
}
data "aws_caller_identity" "current" {}
locals {
  name     = "togglemaster-${var.environment}"
  services = toset(["auth-service", "flag-service", "targeting-service", "evaluation-service", "analytics-service"])
  databases = {
    auth      = "auth_db"
    flags     = "flags_db"
    targeting = "targeting_db"
  }
  cluster_role = aws_iam_role.cluster[0].arn
  node_role    = aws_iam_role.nodes[0].arn
}
module "network" {
  source = "./modules/network"
  name   = local.name
}
