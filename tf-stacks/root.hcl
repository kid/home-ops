locals {
  cloudflare = yamldecode(sops_decrypt_file("${get_repo_root()}/secrets/cloudflare.sops.yaml"))

  env_config = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  stack_config = try(read_terragrunt_config(find_in_parent_folders("stack.hcl")), { locals = {} })
  
  environment = local.env_config.locals.environment

  routeros_inputs = try(yamldecode(sops_decrypt_file("${get_repo_root()}/secrets/${local.environment}/routeros.sops.yaml")), {})
  proxmox_inputs = try(yamldecode(sops_decrypt_file("${get_repo_root()}/secrets/proxmox.sops.yaml")), { })
}

inputs = merge(
  local.env_config.locals,
  local.stack_config.locals,
  local.routeros_inputs,
  local.proxmox_inputs,
)

# generate "backend" {
#   path = "backend.tf"
#   if_exists = "overwrite_terragrunt"
#   contents = <<EOF
#     terraform {
#       backend "s3" {
#         bucket = "terragrunt"
#         key = "home-ops/${path_relative_to_include()}/tofu.tfstate"
#         region = "auto"
#         skip_credentials_validation = true
#         skip_metadata_api_check = true
#         skip_region_validation = true
#         skip_requesting_account_id = true
#         skip_s3_checksum = true
#         use_path_style = true
#         access_key = "${local.cloudflare.r2_access_key}"
#         secret_key = "${local.cloudflare.r2_secret_key}"
#         endpoints = {
#           s3 = "${local.cloudflare.r2_endpoint}"
#         }
#       }
#     }
#   EOF
# }

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
    use_path_style                = true
    
    
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
