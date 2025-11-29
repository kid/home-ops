generate "provider_routeros" {
  path      = "provider_routeros.tofu"
  if_exists = "overwrite_terragrunt"
  contents  = file("provider-routeros.tofu")
}

generate "provider_routeros_script" {
  path      = "get_ros_endpoint.sh"
  if_exists = "overwrite_terragrunt"
  contents  = file("get_ros_endpoint.sh")
}
