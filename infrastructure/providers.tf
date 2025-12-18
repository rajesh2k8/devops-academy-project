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
    bucket         = "gl-capstone-project-pan-2025"
    key            = "envs/dev/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "gl-capstone-project-pan-2025"
    encrypt        = true
  }
}

provider "aws" {
  region = var.region
}
