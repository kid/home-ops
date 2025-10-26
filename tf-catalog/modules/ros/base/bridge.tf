resource "routeros_interface_bridge" "bridge" {
  name           = var.bridge_name
  comment        = var.bridge_comment
  mtu            = var.bridge_mtu
  vlan_filtering = true
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
