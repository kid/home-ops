terraform {
  required_providers {
    onepassword = {
      source  = "1Password/onepassword"
      version = "~> 3.0"
    }
  }
}

variable "op_vault" {
  type        = string
  description = "1Password vault name or UUID the kanidm item is written to"
}

variable "smtp_password" {
  type        = string
  sensitive   = true
  description = "Google app password of the Gmail account Kanidm sends from"
}

provider "onepassword" {}

data "onepassword_vault" "this" {
  name = var.op_vault
}

# Read by modules/den/aspects/kubernetes/kanidm/default.nix's ExternalSecret as kanidm/secrets/<field>.
resource "onepassword_item" "kanidm" {
  vault    = data.onepassword_vault.this.uuid
  title    = "kanidm"
  category = "secure_note"

  section {
    label = "secrets"

    field {
      label = "smtp-password"
      type  = "CONCEALED"
      value = replace(var.smtp_password, " ", "") # Google shows it in groups of four
    }
  }
}
