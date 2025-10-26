module "dhcp-server" {
  for_each       = var.vlans
  source         = "../../../modules/ros/dhcp-server"
  interface_name = each.value.name
  cidr           = each.value.cidr
  gateway        = each.value.gateway
  dhcp_ranges    = each.value.dhcp_pool
  dns_servers    = each.value.dns_servers
  domain         = each.value.domain
  static_leases = { for idx, lease in var.static_leases : lease.address => {
    mac  = lease.mac
    name = lease.name
    } if lease.vlan == each.value.name
  }
}
