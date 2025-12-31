locals {
  interface_vlan_ids = [
    for _, x in distinct(flatten([
      for _, iface in var.ethernet_interfaces : concat(iface.tagged, [iface.untagged])
    ])) : x
    if x != null
  ]

  bridge_vlan_assignments = {
    for _, vlan_id in local.interface_vlan_ids : vlan_id => {
      vlan_ids = [vlan_id]
      tagged   = [for iface_name, iface in var.ethernet_interfaces : iface_name if contains(iface.tagged, vlan_id)]
      untagged = [for iface_name, iface in var.ethernet_interfaces : iface_name if iface.untagged == vlan_id]
    }
  }
}

resource "routeros_interface_vlan" "vlans" {
  for_each = var.vlans

  interface = routeros_interface_bridge.bridge.name
  name      = each.value.name
  vlan_id   = each.value.vlan_id
  mtu       = each.value.mtu
}

resource "routeros_interface_bridge_vlan" "bridge_vlans" {
  for_each = local.bridge_vlan_assignments

  bridge   = routeros_interface_bridge.bridge.name
  vlan_ids = each.value.vlan_ids

  tagged   = concat([routeros_interface_bridge.bridge.name], each.value.tagged)
  untagged = each.value.untagged
}
