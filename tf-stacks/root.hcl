locals {
  environment = local.env_config.locals.environment

  cloudflare     = yamldecode(sops_decrypt_file("${get_repo_root()}/secrets/cloudflare.sops.yaml"))
  proxmox_inputs = try(yamldecode(sops_decrypt_file("${get_repo_root()}/secrets/proxmox.sops.yaml")), {})

  env_config     = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  network_config = try(read_terragrunt_config(find_in_parent_folders("network.hcl")), { locals = {} })

  hostname = try(regex("${local.environment}/network/(?P<hostname>\\w*)", path_relative_to_include()).hostname, null)

  base_cfg = try(read_terragrunt_config(find_in_parent_folders("base.hcl")).locals, {})

  base_inputs = merge(
    {
      routeros_secrets_path = "${get_repo_root()}/secrets/${local.environment}/routeros.sops.yaml"
    },
    try(local.base_cfg.shared_inputs, {}),
    try(local.base_cfg.per_device_inputs[local.hostname], {}),
  )

  routeros_inputs = {
    routeros_endpoint     = try(local.base_inputs.routeros_endpoint, null)
    routeros_secrets_path = "${get_repo_root()}/secrets/${local.environment}/routeros.sops.yaml"
  }
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
    key     = "home-ops/${path_relative_to_include()}/tofu.tfstate"
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
