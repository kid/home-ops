locals {
  ros = read_terragrunt_config(find_in_parent_folders("ros.hcl"))
}

generate "provider-ros" {
  path = "provider-ros.tf"
  if_exists = "overwrite_terragrunt"
  contents = file("provider-ros.tf")
}

inputs = local.ros.inputs
