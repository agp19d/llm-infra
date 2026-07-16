output "github_actions_role_arn" {
  description = "Paste into the AWS_ROLE_ARN repo variable / .github/workflows/*.yml -- the role CI assumes via OIDC."
  value       = aws_iam_role.github_actions.arn
}

output "state_bucket" {
  description = "Must match the `bucket` value in infra/versions.tf's backend \"s3\" block."
  value       = aws_s3_bucket.tfstate.bucket
}
