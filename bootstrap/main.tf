locals {
  common_tags = {
    Project = "llm-infra-bootstrap"
  }
}

# ---------------------------------------------------------------------------
# Terraform state bucket for infra/ -- versioned so a bad apply's state is
# recoverable, encrypted, and fully private. infra/'s backend "s3" block
# uses native S3 locking (use_lockfile), so no DynamoDB table is needed.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "tfstate" {
  bucket = var.state_bucket_name

  tags = merge(local.common_tags, { Name = "llm-infra-tfstate" })
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# GitHub OIDC federation -- lets GitHub Actions assume an AWS role with a
# short-lived token instead of a stored access key. Thumbprint is GitHub's
# well-known OIDC intermediate CA; AWS ignores it for GitHub/GitLab OIDC as
# of 2023 but the provider resource still requires a value.
# https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services
# ---------------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = local.common_tags
}

data "aws_iam_policy_document" "github_actions_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "llm-infra-github-actions"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume.json

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Permissions for the CI role -- everything infra/ needs to plan/apply/
# destroy the GPU box stack, plus read/write on its own state bucket.
# IAM permissions are scoped to the dead-man-switch's scheduler role by name
# (infra/main.tf's aws_iam_role.scheduler) rather than granted account-wide.
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "github_actions" {
  statement {
    sid       = "Ec2Management"
    effect    = "Allow"
    actions   = ["ec2:*"]
    resources = ["*"]
  }

  statement {
    sid    = "SchedulerRoleManagement"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:TagRole",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:PassRole",
    ]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/disposable-dev-scheduler-role"]
  }

  statement {
    sid       = "SchedulerManagement"
    effect    = "Allow"
    actions   = ["scheduler:*"]
    resources = ["*"]
  }

  statement {
    sid       = "AmiLookup"
    effect    = "Allow"
    actions   = ["ssm:GetParameter"]
    resources = ["arn:aws:ssm:*:*:parameter/aws/service/deeplearning/*"]
  }

  statement {
    sid    = "TfStateBucket"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${aws_s3_bucket.tfstate.arn}/*"]
  }

  statement {
    sid       = "TfStateBucketList"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.tfstate.arn]
  }
}

resource "aws_iam_role_policy" "github_actions" {
  name   = "llm-infra-ci"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_actions.json
}
