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

variable "github_owner" {
  type = string
}

variable "github_repo" {
  type = string
}

variable "webhook_hostname" {
  type = string
}

variable "receiver_name" {
  type = string
}

variable "receiver_namespace" {
  type = string
}

# Must match flux/webhook.nix's ExternalSecret remoteRef.key item.
variable "token_item" {
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

resource "random_password" "token" {
  length  = 40
  special = false
}

resource "onepassword_item" "token" {
  vault    = data.onepassword_vault.home_ops_prd.uuid
  title    = var.token_item
  category = "secure_note"

  section {
    label = "credentials"

    field {
      label = "token"
      type  = "CONCEALED"
      value = random_password.token.result
    }
  }
}

# notification-controller's Receiver path: /hook/sha256(token + name + namespace).
resource "github_repository_webhook" "flux" {
  repository = var.github_repo

  configuration {
    url          = "https://${var.webhook_hostname}/hook/${sha256("${random_password.token.result}${var.receiver_name}${var.receiver_namespace}")}"
    content_type = "json"
    secret       = random_password.token.result
    insecure_ssl = false
  }

  active = true
  events = ["push"]
}
