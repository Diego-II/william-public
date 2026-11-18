# infra/ (optional)

There is **no server infrastructure** — William runs on a home laptop. This module only
provisions the two optional AWS bits:

- a dedicated **`william-bedrock` IAM user** (Bedrock invoke only) for the LiteLLM proxy, and
- an optional **versioned S3 bucket** for `~/.hermes` state backups.

```bash
cd infra
terraform init
terraform apply                       # add -var enable_backup_bucket=true to create the bucket
terraform output -raw bedrock_secret_access_key   # → AWS_SECRET_ACCESS_KEY in the box's .env
```

Skip this entirely if you only use Gemini (the default) and back up locally.
