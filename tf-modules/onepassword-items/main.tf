# 1Password vault items whose *layout* (title/category/field names) is
# Nix-declared — modules/kubernetes/_secrets-lib.nix's mkOnePasswordItem,
# collected by modules/den/policies/cluster.nix's
# cluster-to-onepassword-items policy, rendered by
# modules/terragrunt/collect.nix into the `items` variable below. Fixes the
# vault-layout-drift pain point: the same spec also drives each app's
# ExternalSecret (mkExternalSecretData), so a field can't exist on one side
# without the other.
#
# `service_account_token` is deliberately absent from the provider block —
# the 1Password provider reads it from the OP_SERVICE_ACCOUNT_TOKEN
# environment variable on its own, so it never touches a .tfvars file or
# Terraform state.
terraform {
  required_providers {
    onepassword = {
      source  = "1Password/onepassword"
      version = "~> 3.3"
    }
  }
}

provider "onepassword" {}

variable "items" {
  description = "1Password items to create/manage, one per app secret spec."
  type = list(object({
    title    = string
    vault    = string
    category = string
    fields = list(object({
      name     = string
      generate = bool
      length   = number
    }))
  }))
}

# Only the vault names actually referenced, so a typo'd vault name fails
# fast with a clear "vault not found" error instead of silently creating a
# data source no item uses.
data "onepassword_vault" "vaults" {
  for_each = toset([for item in var.items : item.vault])
  name     = each.value
}

# Every custom field lives in one fixed section ("fields") so ESO's remote
# reference format (<item>/<section>/<field>, external-secrets.io/main/
# provider/1password-sdk) stays predictable — mkExternalSecretData builds
# the exact same "<title>/fields/<name>" path.
resource "onepassword_item" "items" {
  for_each = { for item in var.items : item.title => item }

  vault    = data.onepassword_vault.vaults[each.value.vault].uuid
  title    = each.value.title
  category = each.value.category

  section_map = {
    fields = {
      field_map = {
        for field in each.value.fields : field.name => {
          type  = "CONCEALED"
          value = field.generate ? null : ""
          password_recipe = field.generate ? {
            length  = field.length
            digits  = null
            symbols = null
          } : null
        }
      }
    }
  }

  # Once created, Terraform never touches section_map contents again: a
  # generate=false field's value is meant to be filled in by hand (or
  # secretspec) afterward, and re-applying must not reset it back to "".
  # Trade-off, deliberate: changing a field's shape later (add/rename/
  # regenerate) needs a manual `terraform taint`/recreate, not a plain
  # re-apply — acceptable for a home cluster's low change rate.
  lifecycle {
    ignore_changes = [section_map]
  }
}
