terraform {
    required_version = ">= 1.10.0"

    backend "s3" {
      bucket        = "tc-fase-03-tfstate-bucket"
      key           = "fase3/terraform.tfstate"
      region        = "us-east-2"
      use_lockfile  = true
    }

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
