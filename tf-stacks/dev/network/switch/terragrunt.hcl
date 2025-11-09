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
}

dependencies {
  paths = ["../router"]
}

locals {
  hostname        = "switch"
  interface_lists = include.root.locals.env_config.locals.interface_lists
  vlans           = include.root.locals.env_config.locals.vlans
  all_vlans       = keys(local.vlans)
}

inputs = merge(
  include.root.locals.routeros_inputs,
  include.root.locals.env_config.inputs,
  {
    hostname = local.hostname

    ethernet_interfaces = {
      ether1 = { comment = "oob", bridge_port = false, interface_lists = [local.interface_lists.MANAGEMENT] }
      ether2 = { comment = "router", bridge_port = true, tagged = local.all_vlans }
      ether3 = { comment = "trusted2", bridge_port = true, untagged = local.vlans.Trusted.name }
      ether4 = { comment = "guest2", bridge_port = true, untagged = local.vlans.Guest.name }
    }

    dhcp_clients = [{ interface = local.vlans.Management.name }]
  },
)
