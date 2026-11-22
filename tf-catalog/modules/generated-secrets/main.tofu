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
  }
}

# The cluster's vault, which its `onepassword` ClusterSecretStore reads.
variable "vault" {
  type = string
}

# 1Password item title -> the password generated into its one field, in the
# item's `credentials` section; the rest are random_password's arguments.
# Emitted by the app aspects through the generated-secrets quirk
# (modules/den/quirks/generated-secrets.nix).
variable "items" {
  type = map(object({
    field            = string
    length           = number
    upper            = optional(bool, true)
    lower            = optional(bool, true)
    numeric          = optional(bool, true)
    special          = optional(bool, true)
    min_upper        = optional(number, 0)
    min_lower        = optional(number, 0)
    min_numeric      = optional(number, 0)
    min_special      = optional(number, 0)
    override_special = optional(string)
  }))
}

provider "onepassword" {}

data "onepassword_vault" "this" {
  name = var.vault
}

resource "random_password" "this" {
  for_each = var.items

  length           = each.value.length
  upper            = each.value.upper
  lower            = each.value.lower
  numeric          = each.value.numeric
  special          = each.value.special
  min_upper        = each.value.min_upper
  min_lower        = each.value.min_lower
  min_numeric      = each.value.min_numeric
  min_special      = each.value.min_special
  override_special = each.value.override_special

  # The apps keep copies of these values in their own settings, so the
  # arguments only shape a new password: changing one never regenerates it.
  # This also keeps a password adopted with `tofu import` (by value), which
  # records every argument at random_password's defaults, from being
  # replaced. Rotate one deliberately with `apply -replace`.
  lifecycle {
    ignore_changes = [
      length,
      upper,
      lower,
      numeric,
      special,
      min_upper,
      min_lower,
      min_numeric,
      min_special,
      override_special,
    ]
  }
}

resource "onepassword_item" "this" {
  for_each = var.items

  vault    = data.onepassword_vault.this.uuid
  title    = each.key
  category = "secure_note"

  section {
    label = "credentials"

    field {
      label = each.value.field
      type  = "CONCEALED"
      value = random_password.this[each.key].result
    }
  }
}
