variable "region" {
  description = "AWS region for the state bucket and the OIDC role's default region."
  type        = string
  default     = "us-east-1"
}

variable "github_repo" {
  description = <<-EOT
    GitHub repo allowed to assume the CI role, as "owner/name".
    Scopes the OIDC trust policy so only workflows running in this repo
    (any branch, PR, or workflow_dispatch) can assume the role.
  EOT
  type        = string
  default     = "agp19d/llm-infra"
}

variable "state_bucket_name" {
  description = <<-EOT
    Globally-unique S3 bucket name for infra/'s Terraform state.
    Must match the `bucket` value in infra/versions.tf's backend "s3" block.
  EOT
  type        = string
  default     = "llm-infra-tfstate-agp19d"
}
