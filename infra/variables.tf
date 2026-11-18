variable "region" {
  type    = string
  default = "us-east-1"
}

variable "enable_backup_bucket" {
  type    = bool
  default = false
}

variable "backup_bucket_name" {
  type    = string
  default = "my-william-backup" # S3 names are global: pick your own
}
