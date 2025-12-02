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

# dependencies {
#   paths = ["../router"]
# }

locals {
  interface_lists = include.root.locals.env_config.locals.interface_lists
  # vlans           = include.root.locals.base_inputs.vlans
  # all_vlans       = keys(local.vlans)
}

inputs = merge(
  include.root.locals.base_inputs,
  {
    hostname          = "crs320"
    routeros_endpoint = "10.99.0.2"

    certificate_alt_names = [
      "DNS:crs320",
      "DNS:crs320.kidibox.net",
      "IP:10.99.0.2",
      "IP:192.168.88.1",
    ]
    # ethernet_interfaces = {
    #   ether1 = { comment = "oob", bridge_port = false, interface_lists = [local.interface_lists.MANAGEMENT] }
    #   ether2 = { comment = "router", bridge_port = true, tagged = local.all_vlans }
    #   ether3 = { comment = "trusted2", bridge_port = true, untagged = local.vlans.Trusted.name }
    #   ether4 = { comment = "guest2", bridge_port = true, untagged = local.vlans.Guest.name }
    # }
  },
)
