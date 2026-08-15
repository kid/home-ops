# OpenBao KV v2 secrets whose *shape* (path/field names) is Nix-declared —
# modules/kubernetes/_secrets-lib.nix's mkOpenBaoItem, collected by
# modules/den/policies/cluster.nix's cluster-to-openbao-items policy,
# rendered by modules/terragrunt/openbao-items.nix into the `items` variable
# below. Fixes the same layout-drift problem the 1Password design solved
# (external-secrets-1password branch/PR #230): the same spec also drives
# each app's ExternalSecret (mkExternalSecretData), so a field can't exist
# on one side without the other.
#
# Requires the KV mount tf-modules/openbao-config already created (applied
# first, by hand — see modules/terragrunt/openbao-items.nix's own comment on
# why this isn't a Terragrunt `dependencies` block).
terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

variable "address" {
  description = "OpenBao server address, e.g. http://openbao.kidibox.net:8200."
  type        = string
}

variable "root_token" {
  description = "OpenBao root token from `bao operator init`, sourced from secrets/prd/openbao-init.sops.yaml — never stored in Terraform state beyond this run."
  type        = string
  sensitive   = true
}

variable "kv_mount" {
  description = "Path the KV v2 secrets engine is mounted at (tf-modules/openbao-config creates it)."
  type        = string
}

variable "items" {
  description = "OpenBao KV secrets to create/manage, one per app secret spec."
  type = list(object({
    path = string
    fields = list(object({
      name     = string
      generate = bool
      length   = number
    }))
  }))
}

provider "vault" {
  address = var.address
  token   = var.root_token
}

# Flattens every item's generate=true fields into one map keyed by
# "<path>/<field name>", since random_password needs a flat for_each — an
# item's own fields list can't be for_each'd directly.
locals {
  generated_fields = merge([
    for item in var.items : {
      for field in item.fields : "${item.path}/${field.name}" => field.length
      if field.generate
    }
  ]...)
}

resource "random_password" "generated" {
  for_each = local.generated_fields
  length   = each.value
  special  = false
}

resource "vault_kv_secret_v2" "items" {
  for_each = { for item in var.items : item.path => item }

  mount = var.kv_mount
  name  = each.value.path

  data_json = jsonencode({
    for field in each.value.fields :
    field.name => (field.generate ? random_password.generated["${each.value.path}/${field.name}"].result : "")
  })

  # Once created, Terraform never touches the secret's data again: a
  # generate=false field's value is meant to be filled in by hand (or
  # secretspec) afterward, and re-applying must not reset it back to "".
  # Trade-off, deliberate: changing a field's shape later (add/rename/
  # regenerate) needs a manual `terraform taint`/recreate, not a plain
  # re-apply — acceptable for a home cluster's low change rate. Mirrors
  # tf-modules/onepassword-items' identical section_map ignore_changes.
  lifecycle {
    ignore_changes = [data_json]
  }
}
