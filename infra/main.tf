# OPTIONAL — only needed for the Bedrock model switch and S3 state backup.
# The compute lives on a home laptop, so there is no server infra here.
# Apply with local state (simplest) or configure your own backend.

terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = var.region
}

# Dedicated IAM user for the on-box LiteLLM proxy — Bedrock invoke only.
resource "aws_iam_user" "william_bedrock" {
  name = "william-bedrock"
  tags = { project = "william" }
}

data "aws_iam_policy_document" "bedrock_invoke" {
  statement {
    sid       = "InvokeBedrock"
    actions   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
    resources = ["*"]
  }
}

resource "aws_iam_user_policy" "william_bedrock" {
  name   = "bedrock-invoke"
  user   = aws_iam_user.william_bedrock.name
  policy = data.aws_iam_policy_document.bedrock_invoke.json
}

resource "aws_iam_access_key" "william_bedrock" {
  user = aws_iam_user.william_bedrock.name
}

# Optional versioned bucket for ~/.hermes state backups (set var.enable_backup_bucket=true).
resource "aws_s3_bucket" "backup" {
  count  = var.enable_backup_bucket ? 1 : 0
  bucket = var.backup_bucket_name
  tags   = { project = "william" }
}

resource "aws_s3_bucket_versioning" "backup" {
  count  = var.enable_backup_bucket ? 1 : 0
  bucket = aws_s3_bucket.backup[0].id
  versioning_configuration { status = "Enabled" }
}
