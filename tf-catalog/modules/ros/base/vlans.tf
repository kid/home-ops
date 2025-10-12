resource "routeros_interface_vlan" "vlans" {
  for_each = var.vlans

  interface = var.bridge_name
  name      = each.value.name
  vlan_id   = each.value.vlan_id
  mtu       = each.value.mtu
}
