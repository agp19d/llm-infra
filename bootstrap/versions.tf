terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Deliberately local state: this stack creates the S3 bucket that infra/
  # uses as its backend, so it can't use that bucket as its own backend.
  # Small (4 resources), applied by hand, rarely touched -- local state is
  # fine. Keep terraform.tfstate here safe; it's gitignored.
}

provider "aws" {
  region = var.region
}
