variable "account_id" {
  type = string
}

variable "environment" {
  type = string
}

module "bucket" {
  source = "../cloudflare-r2-bucket"

  account_id  = var.account_id
  bucket_name = "home-ops-${var.environment}-kopiur"
  token_name  = "kopiur@home-ops/${var.environment}"
}

output "access_key_id" {
  value = module.bucket.access_key_id
}

output "secret_access_key" {
  value     = module.bucket.secret_access_key
  sensitive = true
}
