resource "routeros_ip_address" "vlans" {
  for_each  = { for k, v in var.vlans : k => v if v.ip_address != null }
  interface = routeros_interface_vlan.vlans[each.key].name
  address   = each.value.ip_address
}

resource "routeros_ip_address" "ethernet" {
  for_each  = { for k, v in var.ethernet_interfaces : k => v if v.ip_address != null }
  interface = routeros_interface_ethernet.ethernet[each.key].name
  address   = each.value.ip_address
}
