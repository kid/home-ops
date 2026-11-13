terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
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

# Read-only access for restore-only clusters (den.clusters.<name>.kopiur.backups
# = false): R2 refuses their writes, whatever kopiur is configured to do.
data "cloudflare_account_api_token_permission_groups_list" "r2_read" {
  account_id = var.account_id
  name       = "Workers%20R2%20Storage%20Bucket%20Item%20Read"
}

resource "cloudflare_account_token" "readonly" {
  account_id = var.account_id
  name       = "kopiur-readonly@home-ops/${var.environment}"

  policies = [{
    effect = "allow"
    permission_groups = [
      { id = data.cloudflare_account_api_token_permission_groups_list.r2_read.result[0].id }
    ]
    resources = jsonencode({
      "com.cloudflare.edge.r2.bucket.${var.account_id}_default_${module.bucket.bucket_name}" = "*"
    })
  }]
}

resource "onepassword_item" "kopiur_r2_readonly" {
  vault    = data.onepassword_vault.home_ops_prd.uuid
  title    = "kopiur-r2-readonly-credentials"
  category = "secure_note"

  section {
    label = "credentials"

    field {
      label = "access-key-id"
      type  = "STRING"
      value = cloudflare_account_token.readonly.id
    }

    field {
      label = "secret-access-key"
      type  = "CONCEALED"
      value = sha256(cloudflare_account_token.readonly.value)
    }

    field {
      label = "repository-password"
      type  = "CONCEALED"
      value = random_password.kopia_repository_password.result
    }
  }
}
