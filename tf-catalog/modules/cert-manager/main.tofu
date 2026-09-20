terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
    onepassword = {
      source  = "1Password/onepassword"
      version = "~> 3.0"
    }
  }
}

variable "cluster_name" {
  type = string
}

variable "account_id" {
  type = string
}

variable "domain" {
  type = string
}

provider "onepassword" {}

data "onepassword_vault" "home_ops_prd" {
  name = "home-ops-prd"
}

data "cloudflare_zone" "this" {
  filter = {
    name    = var.domain
    account = { id = var.account_id }
  }
}

data "cloudflare_account_api_token_permission_groups_list" "dns_write" {
  account_id = var.account_id
  name       = "DNS%20Write" # TODO: confirm the exact permission group name at apply time
}

resource "cloudflare_account_token" "dns" {
  account_id = var.account_id
  name       = "cert-manager-dns01-${var.cluster_name}"

  policies = [{
    effect = "allow"
    permission_groups = [
      { id = data.cloudflare_account_api_token_permission_groups_list.dns_write.result[0].id }
    ]
    resources = jsonencode({
      "com.cloudflare.api.account.zone.${data.cloudflare_zone.this.zone_id}" = "*"
    })
  }]
}

resource "onepassword_item" "cloudflare_dns_api_token" {
  vault    = data.onepassword_vault.home_ops_prd.uuid
  title    = "cloudflare-dns-api-token"
  category = "secure_note"

  section {
    label = "credentials"

    field {
      label = "token"
      type  = "CONCEALED"
      value = cloudflare_account_token.dns.value
    }
  }
}
