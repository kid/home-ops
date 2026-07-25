locals {
  cloudflare = yamldecode(sops_decrypt_file("${get_repo_root()}/secrets/cloudflare.sops.yaml"))
}

remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    endpoints = {
      s3 = "${local.cloudflare.r2_endpoint}"
    }

    access_key = "${local.cloudflare.r2_access_key}"
    secret_key = "${local.cloudflare.r2_secret_key}"

    bucket  = "terragrunt"
    key     = "home-ops/${replace(path_relative_to_include(), ".terragrunt-stack/", "")}/tofu.tfstate"
    region  = "auto"
    encrypt = true

    # Force path-style URLs for Cloudflare R2 compatibility
    use_path_style = true

    # Enable S3 locking (instead of DynamoDB)
    use_lockfile = true

    # Skip AWS-specific validations for Cloudflare R2
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true

    # Additional S3-compatible storage compatibility flags
    skip_s3_checksum             = true
    disable_aws_client_checksums = true
  }
}
