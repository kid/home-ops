include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

include "provider_routeros" {
  path   = "${get_repo_root()}/tf-catalog/modules/_shared/provider-routeros.hcl"
  expose = true
}

terraform {
  source = "${get_repo_root()}/tf-catalog//modules/ros/router"
}

dependencies {
  paths = ["../"]
}

dependency "lab" {
  config_path = "../../../lab"
}

locals {
  hostname = "router"
  vlans    = include.root.locals.env_config.locals.vlans
}

inputs = merge(
  include.root.inputs,
  {
    routeros_endpoint    = "https://${dependency.lab.outputs.oob_ips[local.hostname]}",
    wan_interface        = "ether2"
    dns_upstream_servers = ["1.1.1.1", "8.8.8.8"]

    vlans_forward_rules = {
      "${local.vlans.Management.name}" = [
        { action = "accept", dst_interface_list = "WAN", comment = "Allow WAN from Management" },
      ]
      "${local.vlans.Trusted.name}" = [
        { action = "accept", dst_interface_list = "WAN", comment = "Allow WAN from Trusted" },
        { action = "accept", dst_interface = local.vlans.Management.name, comment = "Allow access to Management from Trusted" },
      ]
    }
  },
)
