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
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
  }
}

variable "cluster_name" {
  type = string
}

variable "account_id" {
  type = string
}

variable "cloudflare_zone_id" {
  type = string
}

variable "vault_address" {
  type = string
}

provider "onepassword" {}

data "onepassword_vault" "home_ops_prd" {
  name = "home-ops-prd"
}

data "onepassword_item" "openbao_approle" {
  vault = data.onepassword_vault.home_ops_prd.uuid
  title = "openbao-approle"
}

provider "vault" {
  address = "http://${var.vault_address}:8200"
  # The approle policy can't mint child tokens.
  skip_child_token = true

  auth_login {
    path = "auth/approle/login"
    parameters = {
      role_id   = data.onepassword_item.openbao_approle.username
      secret_id = data.onepassword_item.openbao_approle.password
    }
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
      "com.cloudflare.api.account.zone.${var.cloudflare_zone_id}" = "*"
    })
  }]
}

resource "vault_kv_secret_v2" "cloudflare_dns_api_token" {
  mount = "secret"
  name  = "cloudflare-dns-api-token"
  data_json = jsonencode({
    token = cloudflare_account_token.dns.value
  })
}
