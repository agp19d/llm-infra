terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.13"
    }
  }

  # Bucket and region come from bootstrap/'s outputs -- created once, by hand,
  # in bootstrap/ (this stack can't create the backend it depends on). Native
  # S3 locking (use_lockfile) needs Terraform >= 1.10; no DynamoDB table.
  backend "s3" {
    bucket       = "llm-infra-tfstate-agp19d"
    key          = "infra/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.region
}
