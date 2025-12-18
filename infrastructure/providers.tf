terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
  # Simple local backend; you can switch to S3 later
  backend "s3" {
    bucket         = "devops-academy-project"
    key            = "envs/dev/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "devops-academy-project"
    encrypt        = true
  }
}

provider "aws" {
  region = var.region
}
