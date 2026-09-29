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

data "onepassword_vault" "home_ops_prd" {
  name = "home-ops-prd"
}

# No token set: falls back to `gh auth token` on the machine running apply.
provider "github" {
  owner = var.github_owner
}

resource "random_password" "argocd_github_webhook" {
  length  = 32
  special = false
}

# Must match argocd/default.nix's ExternalSecret remoteRef.key.
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
