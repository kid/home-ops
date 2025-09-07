locals {
  env_config = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  stack_config = try(read_terragrunt_config(find_in_parent_folders("stack.hcl")), { locals = {} })
}

inputs = merge(
  local.env_config.locals,
  local.stack_config.locals,
)

generate "backend" {
  path = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents = <<EOF
    terraform {
      backend "s3" {
        bucket = "tfstate"
        key = "${path_relative_to_include()}/tofu.tfstate"
        encrypt = false
        skip_credentials_validation = true
        skip_requesting_account_id = true
        skip_metadata_api_check = true
        skip_region_validation = true
        use_path_style = true
      }
    }
  EOF
}
