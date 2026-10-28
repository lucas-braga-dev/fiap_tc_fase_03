terraform {
    required_version = ">= 1.5.0"
    required_providers {
        aws = {
            source  = "hashicorp/aws"
            version = "~> 5.0"
        }
    }
}

provider "aws" {
    region = var.aws_region
}

module "ec2_module" {
  source = "./modules/ec2"
}

module "rds_module" {
  source = "./modules/rds"
}

module "s3_module" {
  source = "./modules/s3"
}

module "vpc_module" {
  source = "./modules/vpc"
}
