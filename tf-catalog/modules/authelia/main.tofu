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
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

variable "op_vault" {
  type        = string
  description = "1Password vault name or UUID the authelia item is written to"
}

variable "url" {
  type        = string
  description = "Authelia's public URL, set on each user's login item"
}

variable "smtp_password" {
  type        = string
  sensitive   = true
  description = "Google app password of the Gmail account Authelia sends from"
}

variable "users" {
  type = map(object({
    displayname = string
    email       = string
    groups      = list(string)
  }))
  description = "Authelia users, by username. Each gets a random password, kept in its own 1Password login item."
}

provider "onepassword" {}

data "onepassword_vault" "this" {
  name = var.op_vault
}

locals {
  secret_names = [
    "reset-password-jwt-secret",
    "session-encryption-key",
    "storage-encryption-key",
    "oidc-hmac-secret",
    "argocd-client-secret",
  ]
}

resource "random_password" "secret" {
  for_each = toset(local.secret_names)

  length  = 64
  special = false
}

resource "random_password" "user" {
  for_each = var.users

  length  = 32
  special = false
}

resource "tls_private_key" "oidc_jwks" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Read by modules/den/aspects/kubernetes/authelia/default.nix as authelia/secrets/<field>.
resource "onepassword_item" "authelia" {
  vault    = data.onepassword_vault.this.uuid
  title    = "authelia"
  category = "secure_note"

  section {
    label = "secrets"

    dynamic "field" {
      for_each = random_password.secret

      content {
        label = field.key
        type  = "CONCEALED"
        value = field.value.result
      }
    }

    field {
      label = "smtp-password"
      type  = "CONCEALED"
      value = replace(var.smtp_password, " ", "") # Google shows it in groups of four
    }

    # The next two are multi-line and a concealed field loses its newlines, so they are
    # base64 here and decoded by the ExternalSecret.
    field {
      label = "oidc-jwks-key"
      type  = "CONCEALED"
      value = base64encode(tls_private_key.oidc_jwks.private_key_pem)
    }

    # Authelia's file backend, with bcrypt hashes.
    field {
      label = "users-database"
      type  = "CONCEALED"
      value = base64encode(yamlencode({
        users = {
          for name, user in var.users : name => {
            disabled    = false
            displayname = user.displayname
            email       = user.email
            groups      = user.groups
            password    = random_password.user[name].bcrypt_hash
          }
        }
      }))
    }
  }
}

resource "onepassword_item" "login" {
  for_each = var.users

  vault    = data.onepassword_vault.this.uuid
  title    = "Authelia - user - ${each.key}"
  category = "login"
  url      = var.url
  username = each.key
  password = random_password.user[each.key].result
}
