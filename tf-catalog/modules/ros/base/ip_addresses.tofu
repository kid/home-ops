resource "routeros_ip_address" "addresses" {
  depends_on = [
    routeros_interface_ethernet.ethernet,
    routeros_interface_vlan.vlans,
  ]

  for_each  = var.ip_addresses
  interface = each.key
  address   = each.value
}
