locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("environment.hcl"))
}

inputs = merge(
  local.environment_vars.locals,
)

generate "providers" {
  path = "providers.tf"
  if_exists = "overwrite_terragrunt"
  contents = file(find_in_parent_folders("tf-catalog/modules/ros/_shared/provider.tf"))
}
