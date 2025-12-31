include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

include "provider_routeros" {
  path   = "${get_repo_root()}/tf-catalog/modules/_shared/provider-routeros.hcl"
  expose = true
}

terraform {
  source                   = "${get_repo_root()}/tf-catalog/modules/ros//qos"
  copy_terraform_lock_file = false
}

locals {
  interface_lists = include.root.locals.env_config.locals.interface_lists
}

inputs = merge(
  include.root.locals.base_inputs,
  {
    hostname          = "rb5009"
    routeros_endpoint = "10.99.0.1"

    bridge_name   = "bridge1"
    wan_interface = "ether8"

    limit_tx = "18M"
    limit_rx = "900M"
  },
)
