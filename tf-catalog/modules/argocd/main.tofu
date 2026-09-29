terraform {
  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
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

variable "cluster_name" {
  type = string
}

variable "github_owner" {
  type = string
}

variable "github_repo" {
  type = string
}

variable "webhook_hostname" {
  type = string
}

provider "onepassword" {}

data "onepassword_vault" "home_ops" {
  name = "home-ops"
}

data "onepassword_vault" "home_ops_prd" {
  name = "home-ops-prd"
}

# Fine-grained PAT, scoped to just this repo's "Webhooks: Read and write"
# permission — minted by hand, kept in 1Password. Terraform can't bootstrap
# this itself: there's no API to create a GitHub token from nothing.
data "onepassword_item" "github_webhook_token" {
  vault = data.onepassword_vault.home_ops.uuid
  title = "github-webhook-token"
}

provider "github" {
  token = data.onepassword_item.github_webhook_token.password
  owner = var.github_owner
}

resource "random_password" "argocd_github_webhook" {
  length  = 32
  special = false
}

# title/section/field here must match argocd/default.nix's ExternalSecret
# remoteRef.key ("argocd/secrets/github-webhook-secret") exactly.
resource "onepassword_item" "argocd_github_webhook_secret" {
  vault    = data.onepassword_vault.home_ops_prd.uuid
  title    = "argocd"
  category = "secure_note"

  section {
    label = "secrets"

    field {
      label = "github-webhook-secret"
      type  = "CONCEALED"
      value = random_password.argocd_github_webhook.result
    }
  }
}

resource "github_repository_webhook" "argocd" {
  repository = var.github_repo

  configuration {
    url          = "https://${var.webhook_hostname}/api/webhook"
    content_type = "json"
    secret       = random_password.argocd_github_webhook.result
    insecure_ssl = false
  }

  active = true
  events = ["push"]
}
