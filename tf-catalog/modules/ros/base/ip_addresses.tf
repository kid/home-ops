resource "routeros_ip_address" "self" {
  depends_on = [routeros_interface_vlan.vlans]
  for_each   = var.ip_addresses
  comment    = "${each.key} IP Address"
  interface  = each.key
  address    = each.value
  network    = cidrhost(each.value, 0)
}
