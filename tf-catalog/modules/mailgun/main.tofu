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
  }
}

variable "op_vault" {
  type        = string
  description = "1Password vault name or UUID the mailgun-smtp item is written to"
}

variable "domain" {
  type        = string
  description = "Sending domain, for example mail.kidibox.net"
}

variable "region" {
  type        = string
  description = "Mailgun region of the account, us or eu"
}

variable "cloudflare_zone_id" {
  type = string
}

provider "onepassword" {}

data "onepassword_vault" "this" {
  name = var.op_vault
}

resource "random_password" "smtp" {
  length  = 32
  special = false
}

resource "mailgun_domain" "this" {
  name          = var.domain
  region        = var.region
  smtp_password = random_password.smtp.result
}

# The record ids are only known once the domain exists, so the first apply needs
# -target=mailgun_domain.this before the full one.
resource "cloudflare_dns_record" "sending" {
  for_each = { for record in mailgun_domain.this.sending_records_set : record.id => record }

  zone_id = var.cloudflare_zone_id
  name    = each.value.name
  type    = each.value.record_type
  content = each.value.value
  ttl     = 1
}

# Read by modules/den/aspects/kubernetes/authelia/default.nix as mailgun-smtp/credentials/<field>.
resource "onepassword_item" "mailgun_smtp" {
  vault    = data.onepassword_vault.this.uuid
  title    = "mailgun-smtp"
  category = "secure_note"

  section {
    label = "credentials"

    field {
      label = "username"
      type  = "STRING"
      value = mailgun_domain.this.smtp_login
    }

    field {
      label = "password"
      type  = "CONCEALED"
      value = random_password.smtp.result
    }
  }
}
