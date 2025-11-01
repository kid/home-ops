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

  mock_outputs = {
    oob_ips = {
      router = ""
      switch = ""
    }
  }
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

    dhcp_servers = {
      for name, vlan in local.vlans : name => vlan if lookup(vlan, "dhcp", true)
    }

    dhcp_static_leases = {
      "${local.vlans.Management.name}" = [
        {
          mac     = dependency.lab.outputs.device_mac_addresses.switch["ether2"]
          name    = "switch"
          address = cidrhost(local.vlans.Management.cidr, 2)
        }
      ]
    }

    vlans_forward_rules = {
      "${local.vlans.Management.name}" = [
        { action = "accept", out_interface_list = "WAN", comment = "Allow WAN from Management" },
      ]
      "${local.vlans.Lan.name}" = [
        { action = "accept", out_interface_list = "WAN", comment = "Allow WAN from Lan" },
        { action = "accept", out_interface = local.vlans.Management.name, comment = "Allow access to Management from Trusted" },
      ]
    }
  },
)
