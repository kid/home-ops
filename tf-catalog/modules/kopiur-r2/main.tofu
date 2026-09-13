terraform {
  required_providers {
    onepassword = {
      source  = "1Password/onepassword"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

module "bucket" {
  source = "../cloudflare-r2-bucket"

  bucket_name = "home-ops-kopiur"
}

data "onepassword_vault" "home_ops" {
  name = "home-ops"
}

data "onepassword_item" "cloudflare_admin" {
  vault = data.onepassword_vault.home_ops.uuid
  title = "Cloudflare - admin token"
}

resource "random_password" "kopia_repository_password" {
  length  = 48
  special = false
}

resource "onepassword_item" "kopiur_r2" {
  vault    = data.onepassword_vault.home_ops.uuid
  title    = "kopiur - R2 credentials"
  category = "secure_note"

  section {
    label = "credentials"

    field {
      label = "accessKeyId"
      type  = "STRING"
      value = module.bucket.access_key_id
    }

    field {
      label = "secretAccessKey"
      type  = "CONCEALED"
      value = module.bucket.secret_access_key
    }

    field {
      label = "repositoryPassword"
      type  = "CONCEALED"
      value = random_password.kopia_repository_password.result
    }
  }
}
