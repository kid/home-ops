terraform {
  required_providers {
    onepassword = {
      source  = "1Password/onepassword"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
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

variable "account_id" {
  type = string
}

variable "kopiur_access_key_id" {
  type = string
}

variable "kopiur_secret_access_key" {
  type      = string
  sensitive = true
}

# Set true once OpenBao is up and its approle exists (Stage 4). On a fresh
# bootstrap Vault doesn't exist yet, and this stack is also what produces
# the kopiur R2 credentials Vault's own restore depends on — an
# unconditional vault provider here would recreate that exact circularity.
variable "enable_vault" {
  type    = bool
  default = false
}

variable "vault_role_id" {
  type    = string
  default = null
}

variable "vault_secret_id" {
  type      = string
  default   = null
  sensitive = true
}

# The LoadBalancer IP OpenBao's Service gets assigned (BGP-advertised, see
# den.clusters.prd.networks.loadBalancer) — only known once it's deployed,
# so it's a plain input, not hardcoded here.
variable "vault_address" {
  type    = string
  default = null
}

variable "cloudflare_zone_id" {
  type = string
}

provider "onepassword" {}

data "onepassword_vault" "home_ops_prd" {
  name = "home-ops-prd"
}

data "onepassword_vault" "home_ops" {
  name = "home-ops"
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
  username = "kid"
  password = data.onepassword_item.routeros_admin.credential
  insecure = true
}

provider "vault" {
  address = var.vault_address != null ? "http://${var.vault_address}:8200" : null

  dynamic "auth_login" {
    for_each = var.enable_vault ? [1] : []
    content {
      path = "auth/approle/login"
      parameters = {
        role_id   = var.vault_role_id
        secret_id = var.vault_secret_id
      }
    }
  }
}

# --- kopiur/R2 credentials -> 1Password ---

resource "random_password" "kopia_repository_password" {
  length  = 48
  special = false
}

resource "onepassword_item" "kopiur_r2" {
  vault    = data.onepassword_vault.home_ops_prd.uuid
  title    = "kopiur-r2-credentials"
  category = "secure_note"

  section {
    label = "credentials"

    field {
      label = "access-key-id"
      type  = "STRING"
      value = var.kopiur_access_key_id
    }

    field {
      label = "secret-access-key"
      type  = "CONCEALED"
      value = var.kopiur_secret_access_key
    }

    field {
      label = "repository-password"
      type  = "CONCEALED"
      value = random_password.kopia_repository_password.result
    }
  }
}

# --- external-dns's RouterOS credential -> Vault ---

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
  count = var.enable_vault ? 1 : 0

  mount = "secret"
  name  = "mikrotik-credentials"
  data_json = jsonencode({
    MIKROTIK_PASSWORD = random_password.external_dns.result
  })
}

# --- cert-manager's Cloudflare DNS token -> Vault ---

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
  count = var.enable_vault ? 1 : 0

  mount = "secret"
  name  = "cloudflare-dns-api-token"
  data_json = jsonencode({
    token = cloudflare_account_token.dns.value
  })
}
