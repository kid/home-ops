include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

include "provider_routeros" {
  path   = "${get_repo_root()}/tf-catalog/modules/_shared/provider-routeros.hcl"
  expose = true
}

terraform {
  source = "${get_repo_root()}/tf-catalog/modules/ros//base"
  copy_terraform_lock_file = false
}

dependencies {
  paths = ["../router", "../switch"]
}

locals {
  interface_lists = include.root.locals.env_config.locals.interface_lists
}

inputs = merge(
  include.root.locals.base_inputs,
  {
    ethernet_interfaces = {
      ether1 = { comment = "oob", bridge_port = false, interface_lists = [local.interface_lists.MANAGEMENT] }
    }

    vlans = {}

    dhcp_clients = [{ interface = "ether2" }]
  },
)
