data "routeros_interfaces" "self" {}

locals {
  interfaces_mac_addresses = [
    for _, ifce in data.routeros_interfaces.self.interfaces :
    ifce.mac_address
    if try(var.ethernet_interfaces[ifce.default_name].bridge_port, false)
  ]
}

resource "routeros_interface_bridge" "bridge" {
  name           = var.bridge_name
  comment        = var.bridge_comment
  mtu            = var.bridge_mtu
  vlan_filtering = true

  # Force admin mac to the first bridge port, otherwise it depends on the order terraform created the ports
  auto_mac       = length(local.interfaces_mac_addresses) == 0
  admin_mac      = try(local.interfaces_mac_addresses[0], null)
}

resource "routeros_interface_bridge_port" "ethernet_ports" {
  for_each = { for k, v in var.ethernet_interfaces : k => v if v.bridge_port }

  bridge    = routeros_interface_bridge.bridge.name
  interface = each.key
  comment   = each.value.comment

  # If untagged VLAN is specified, find its VLAN ID
  pvid = (each.value.untagged != null && each.value.untagged != "") ? (
    [for k, v in var.vlans : v.vlan_id if v.name == each.value.untagged][0]
  ) : null
}
