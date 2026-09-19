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
  }
}

variable "cluster_name" {
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

provider "routeros" {
  hosturl  = "https://10.99.0.1"
  username = data.onepassword_item.routeros_admin.username
  password = data.onepassword_item.routeros_admin.password
  insecure = true
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

resource "onepassword_item" "mikrotik_credentials" {
  vault    = data.onepassword_vault.home_ops_prd.uuid
  title    = "mikrotik-credentials"
  category = "secure_note"

  section {
    label = "credentials"

    field {
      label = "password"
      type  = "CONCEALED"
      value = random_password.external_dns.result
    }
  }
}
