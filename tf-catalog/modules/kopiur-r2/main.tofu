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

variable "account_id" {
  type = string
}

variable "environment" {
  type = string
}

provider "onepassword" {}

data "onepassword_vault" "home_ops_prd" {
  name = "home-ops-prd"
}

module "bucket" {
  source = "../cloudflare-r2-bucket"

  account_id  = var.account_id
  bucket_name = "home-ops-${var.environment}-kopiur"
  token_name  = "kopiur@home-ops/${var.environment}"
}

resource "random_password" "kopia_repository_password" {
  length  = 48
  special = false
}

resource "onepassword_item" "kopiur_r2" {
  vault    = data.onepassword_vault.home_ops_prd.uuid
  title    = "kopiur-r2-credentials"
  category = "secure_note"

  section {
    label = "credentials"

    field {
      label = "access-key-id"
      type  = "STRING"
      value = module.bucket.access_key_id
    }

    field {
      label = "secret-access-key"
      type  = "CONCEALED"
      value = module.bucket.secret_access_key
    }

    field {
      label = "repository-password"
      type  = "CONCEALED"
      value = random_password.kopia_repository_password.result
    }
  }
}
