module "dhcp_server" {
  for_each       = var.dhcp_servers
  source         = "../dhcp-server"
  interface_name = each.key
  cidr           = each.value.cidr
  gateway        = coalesce(each.value.gateway, split("/", var.vlans[each.key].ip_address)[0])
  dhcp_ranges    = each.value.dhcp_pool
  dns_servers    = each.value.dns_servers
  domain         = each.value.domain
  static_leases  = lookup(var.dhcp_static_leases, each.key, [])
}
