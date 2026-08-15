# One-time OpenBao bootstrap: KV v2 mount, AppRole auth backend + role +
# read policy for ESO, and the resulting k8s Secret ESO's ClusterSecretStore
# reads (modules/kubernetes/external-secrets/default.nix). OpenBao itself
# has no dedicated Terraform provider (it's Vault-API-compatible; pointing
# hashicorp/vault at it is OpenBao's own documented approach — there is no
# official openbao/openbao provider as of this writing).
#
# Requires OpenBao to already be initialized and unsealed by hand (`bao
# operator init`/`bao operator unseal`) — this module configures an
# already-running OpenBao, it does not bootstrap OpenBao's own storage.
terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
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
  description = "Path to mount the KV v2 secrets engine at."
  type        = string
}

variable "approle_role_name" {
  description = "Name of the AppRole ESO authenticates as."
  type        = string
}

variable "approle_role_id" {
  description = "Fixed, non-secret role_id for the ESO AppRole (avoids round-tripping a Terraform-generated UUID back into Nix)."
  type        = string
}

variable "secret_namespace" {
  description = "Kubernetes namespace to create the AppRole credentials Secret in."
  type        = string
}

variable "secret_name" {
  description = "Name of the Kubernetes Secret holding the AppRole secret_id."
  type        = string
}

provider "vault" {
  address = var.address
  token   = var.root_token
}

# Uses the default kubeconfig (this repo's .envrc sets KUBECONFIG) — the
# human running `terragrunt apply` here already has cluster access, same as
# every other kubectl-driven step in this repo.
provider "kubernetes" {}

resource "vault_mount" "kv" {
  path = var.kv_mount
  type = "kv-v2"
}

resource "vault_policy" "external_secrets_read" {
  name   = "external-secrets-read"
  policy = <<-EOT
    path "${var.kv_mount}/data/*" {
      capabilities = ["read"]
    }
    path "${var.kv_mount}/metadata/*" {
      capabilities = ["list", "read"]
    }
  EOT
}

resource "vault_auth_backend" "approle" {
  type = "approle"
}

resource "vault_approle_auth_backend_role" "external_secrets" {
  backend        = vault_auth_backend.approle.path
  role_name      = var.approle_role_name
  role_id        = var.approle_role_id
  token_policies = [vault_policy.external_secrets_read.name]
  # No expiry as long as the token is renewed within this window — ESO
  # re-authenticates via AppRole itself, so this mainly bounds how long a
  # single fetched token stays usable if renewal is ever missed.
  token_period = 604800 # 7 days
}

resource "vault_approle_auth_backend_role_secret_id" "external_secrets" {
  backend   = vault_auth_backend.approle.path
  role_name = vault_approle_auth_backend_role.external_secrets.role_name
}

resource "kubernetes_secret_v1" "external_secrets_approle" {
  metadata {
    name      = var.secret_name
    namespace = var.secret_namespace
  }

  data = {
    secret_id = vault_approle_auth_backend_role_secret_id.external_secrets.secret_id
  }
}
