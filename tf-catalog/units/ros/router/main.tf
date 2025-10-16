module "dhcp-server" {
  for_each       = var.vlans
  source         = "../../../modules/ros/dhcp-server"
  interface_name = each.value.name
  cidr_network   = each.value.cidr_network
  cidr_prefix    = each.value.cidr_prefix
  gateway        = each.value.gateway
  dhcp_ranges    = each.value.dhcp_pool
  dns_servers    = each.value.dns_servers
  domain         = each.value.domain
  # static_leases  = each.value.static_leases
}
