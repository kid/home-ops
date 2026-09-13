terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
}

variable "bucket_name" {
  type = string
}

variable "location" {
  type    = string
  default = null
}

data "cloudflare_accounts" "this" {}

data "cloudflare_account_api_token_permission_groups_list" "r2_write" {
  account_id = local.account_id
  name       = "Workers%20R2%20Storage%20Bucket%20Item%20Write"
}

locals {
  account_id = data.cloudflare_accounts.this.result[0].id
}

resource "cloudflare_r2_bucket" "this" {
  account_id = local.account_id
  name       = var.bucket_name
  location   = var.location
}

resource "cloudflare_api_token" "this" {
  name = "${var.bucket_name}-r2"

  policies = [{
    effect = "allow"
    permission_groups = [
      { id = data.cloudflare_account_api_token_permission_groups_list.r2_write.result[0].id }
    ]
    resources = jsonencode({
      "com.cloudflare.edge.r2.bucket.${local.account_id}_default_${var.bucket_name}" = "*"
    })
  }]
}

output "bucket_name" {
  value = cloudflare_r2_bucket.this.name
}

output "access_key_id" {
  value = cloudflare_api_token.this.id
}

output "secret_access_key" {
  value     = sha256(cloudflare_api_token.this.value)
  sensitive = true
}
