include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

include "provider_routeros" {
  path = "${get_repo_root()}/tf-catalog/modules/_shared/provider-routeros.hcl"
}

terraform {
  source                   = "${get_repo_root()}/tf-catalog/modules/ros//base"
  copy_terraform_lock_file = false
}

dependencies {
  paths = ["../../lab"]
}

locals {
  interface_lists = include.root.locals.env_config.locals.interface_lists
  vlans           = include.root.locals.base_inputs.vlans
  all_vlans       = [for _, vlan in local.vlans : vlan.vlan_id]
}

inputs = merge(
  include.root.locals.base_inputs,
  {
    ethernet_interfaces = {
      ether1 = { comment = "oob", bridge_port = false, interface_lists = [local.interface_lists.MANAGEMENT] }
      ether2 = { comment = "wan", bridge_port = false, interface_lists = [local.interface_lists.WAN] }
      ether3 = { comment = "switch", tagged = local.all_vlans }
      ether4 = { comment = "trusted1", untagged = local.vlans.Trusted.vlan_id }
      ether5 = { comment = "guest1", untagged = local.vlans.Guest.vlan_id }
    }

    dhcp_clients = [{ interface = "ether2" }]
    dhcp_servers = {
      for name, vlan in local.vlans : name => merge(vlan, {
        gateway     = split("/", vlan.ip_address)[0]
        dns_servers = [split("/", vlan.ip_address)[0]]
      }) if lookup(vlan, "dhcp", true)
    }
  },
)
