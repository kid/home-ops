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

# Repositories whose issue and pull request events schedule their own run.
variable "repositories" {
  type = list(string)
}

# Repositories whose CI schedules a run through /webhook/v1/schedule.
variable "dispatch_repositories" {
  type = list(string)
}

variable "webhook_url" {
  type = string
}

# Must match renovate/default.nix's webhookItem.
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

# The operator checks X-Hub-Signature-256 against the same token. Managed
# here rather than by the operator's webhook sync, which would need the App
# to write repository webhooks.
resource "github_repository_webhook" "renovate" {
  for_each   = toset(var.repositories)
  repository = each.key

  configuration {
    url          = var.webhook_url
    content_type = "json"
    secret       = random_password.token.result
    insecure_ssl = false
  }

  active = true
  events = ["issues", "pull_request"]
}

# Bearer token for /webhook/v1/schedule.
resource "github_actions_secret" "webhook_token" {
  for_each        = toset(var.dispatch_repositories)
  repository      = each.key
  secret_name     = "RENOVATE_WEBHOOK_TOKEN"
  plaintext_value = random_password.token.result
}
