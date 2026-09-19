terraform {
  required_providers {
    onepassword = {
      source  = "1Password/onepassword"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    routeros = {
      source  = "terraform-routeros/routeros"
      version = "~> 1.99"
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

variable "vault_address" {
  type = string
}

provider "onepassword" {}

data "onepassword_vault" "home_ops" {
  name = "home-ops"
}

data "onepassword_vault" "home_ops_prd" {
  name = "home-ops-prd"
}

# The routeros provider connects as whichever fleet user op_item_routeros
# names for rb5009 (see modules/den/routerosDevices/rb5009.nix) — same
# convention the ros-* Terragrunt stacks already use.
data "onepassword_item" "routeros_admin" {
  vault = data.onepassword_vault.home_ops.uuid
  title = "RB5009 - user - kid"
}

data "onepassword_item" "openbao_approle" {
  vault = data.onepassword_vault.home_ops_prd.uuid
  title = "openbao-approle"
}

provider "routeros" {
  hosturl  = "https://10.99.0.1"
  username = data.onepassword_item.routeros_admin.username
  password = data.onepassword_item.routeros_admin.password
  insecure = true
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

resource "random_password" "external_dns" {
  length  = 32
  special = false
}

resource "routeros_system_user_group" "external_dns" {
  name   = "external-dns"
  policy = ["api", "read", "rest-api", "write"]
}

resource "routeros_system_user" "external_dns" {
  name     = "external-dns-${var.cluster_name}"
  group    = routeros_system_user_group.external_dns.name
  password = random_password.external_dns.result
}

resource "vault_kv_secret_v2" "mikrotik_credentials" {
  mount = "secret"
  name  = "mikrotik-credentials"
  data_json = jsonencode({
    MIKROTIK_PASSWORD = random_password.external_dns.result
  })
}
