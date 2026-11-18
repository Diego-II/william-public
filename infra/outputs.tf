output "bedrock_access_key_id" {
  value     = aws_iam_access_key.william_bedrock.id
  sensitive = true
}

output "bedrock_secret_access_key" {
  value     = aws_iam_access_key.william_bedrock.secret
  sensitive = true
}

output "next_steps" {
  value = "Put the two outputs into the box's .env as AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY (terraform output -raw bedrock_secret_access_key)."
}
