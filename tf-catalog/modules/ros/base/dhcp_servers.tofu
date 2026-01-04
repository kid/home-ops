module "dhcp_server" {
  depends_on     = [routeros_ip_address.addresses]
  for_each       = var.dhcp_servers
  source         = "../dhcp-server"
  interface_name = each.key
  cidr           = each.value.cidr
  gateway        = each.value.gateway
  dhcp_ranges    = each.value.dhcp_pool
  dns_servers    = each.value.dns_servers
  domain         = each.value.domain
  static_leases  = lookup(var.dhcp_static_leases, each.key, [])
}
