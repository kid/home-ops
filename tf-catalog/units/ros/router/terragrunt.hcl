include "root" {
  path = find_in_parent_folders("root.hcl")
  expose = true
}

include "provider_routeros" {
  path = "${get_repo_root()}/tf-catalog/modules/_shared/provider-routeros.hcl"
  expose = true
}

terraform {
  source = "${get_repo_root()}/tf-catalog//modules/ros/router"
}

dependency "lab" {
  config_path = values.lab_path

  mock_outputs = {
    oob_ips = { 
      router = "" 
      switch = ""
    }
    device_mac_addresses = {}
  }
}

dependencies {
  paths = ["../base"]
}

locals {
  vlans = include.root.locals.env_config.locals.vlans
}

inputs = merge(
  include.root.inputs,
  {
    routeros_endpoint = "https://${dependency.lab.outputs.oob_ips[values.hostname]}",
    static_leases = [
      for idx, device_name in [for name, _ in dependency.lab.outputs.device_mac_addresses : name if name != values.hostname] : {
        name = device_name
        vlan = local.vlans.Management.name
        mac = dependency.lab.outputs.device_mac_addresses[device_name]["ether2"]
        address = cidrhost("${local.vlans.Management.cidr_network}/${local.vlans.Management.cidr_prefix}", idx + 2)
      }
    ]
  },
  values
)
