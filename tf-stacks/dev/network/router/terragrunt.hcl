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
  paths = ["base"]
}

locals {
  hostname        = "router"
  interface_lists = include.root.locals.env_config.locals.interface_lists
  vlans           = include.root.locals.env_config.locals.vlans
  devices         = include.root.locals.devices.devices_map
}

inputs = merge(
  include.root.locals.routeros_inputs,
  include.root.locals.env_config.inputs,
  {
    dns_upstream_servers = ["1.1.1.1", "8.8.8.8"]

    dhcp_servers = {
      for name, vlan in local.vlans : name => vlan if lookup(vlan, "dhcp", true)
    }

    dhcp_static_leases = {
      "${local.vlans.Management.name}" = [
        {
          # Broken, not choosing correct, Management vlan has a different mac
          mac     = [for _, ifce in local.devices.switch.interfaces : ifce.mac_address if ifce.name == "ether2"][0]
          name    = "switch"
          address = cidrhost(local.vlans.Management.cidr, 2)
        }
      ]
    }

    vlans = local.vlans

    vlans_input_rules = {
      "${local.vlans.Trusted.name}" = [
        { action = "accept", dst_address = cidrhost(local.vlans.Management.cidr, 1), comment = "Allow access to Management from Trusted" },
      ]
    }

    vlans_forward_rules = {
      "${local.vlans.Management.name}" = [
        { action = "accept", out_interface_list = "WAN", comment = "Allow WAN from Management" },
      ]
      "${local.vlans.Trusted.name}" = [
        { action = "accept", out_interface_list = "WAN", comment = "Allow WAN from Trusted" },
        { action = "accept", out_interface = local.vlans.Management.name, comment = "Allow access to Management from Trusted" },
      ]
      "${local.vlans.Guest.name}" = [
        { action = "accept", out_interface_list = "WAN", comment = "Allow WAN from Guest" },
      ]
    }
  },
)
