terraform {
  required_version = ">= 1.7, < 2.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project   = "likelion-team01"
      Owner     = "chaneee93"
      Env       = var.environment
      ManagedBy = "terraform"
    }
  }
}
