terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
    mailgun = {
      source  = "wgebis/mailgun"
      version = "~> 0.10"
    }
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

variable "mail_domain" {
  type        = string
  description = "Mailgun sending domain, for example mail.kidibox.net"
}

variable "mailgun_region" {
  type        = string
  description = "Mailgun region of the account, us or eu"
}

variable "cloudflare_zone_id" {
  type        = string
  description = "Cloudflare zone that gets the SPF and DKIM records for mail_domain"
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

resource "random_password" "smtp" {
  length  = 32
  special = false
}

resource "tls_private_key" "oidc_jwks" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "mailgun_domain" "this" {
  name          = var.mail_domain
  region        = var.mailgun_region
  smtp_password = random_password.smtp.result
}

# The keys are static because the record set is only known after apply.
locals {
  mailgun_records = {
    spf  = one([for r in mailgun_domain.this.sending_records_set : r if r.record_type == "TXT" && startswith(r.value, "v=spf1")])
    dkim = one([for r in mailgun_domain.this.sending_records_set : r if r.record_type == "TXT" && startswith(r.value, "k=rsa")])
  }
}

resource "cloudflare_dns_record" "mailgun" {
  for_each = local.mailgun_records

  zone_id = var.cloudflare_zone_id
  name    = each.value.name
  type    = each.value.record_type
  content = each.value.value
  ttl     = 1
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
      label = "smtp-username"
      type  = "STRING"
      value = mailgun_domain.this.smtp_login
    }

    field {
      label = "smtp-password"
      type  = "CONCEALED"
      value = random_password.smtp.result
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
