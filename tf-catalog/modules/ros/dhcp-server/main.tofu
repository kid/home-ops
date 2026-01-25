locals {
  default_range = "${cidrhost(var.cidr, 200)}-${cidrhost(var.cidr, 254)}"
}

resource "routeros_ip_pool" "self" {
  comment = "${var.interface_name} DHCP Pool"
  name    = "${var.interface_name}-dhcp-pool"
  ranges  = coalesce(var.dhcp_ranges, [local.default_range])
}

resource "routeros_ip_dhcp_server_network" "self" {
  comment    = "${var.interface_name} DHCP Network"
  address    = var.cidr
  domain     = var.domain
  gateway    = var.gateway
  ntp_server = var.ntp_servers
  dns_server = var.dns_servers
  dns_none   = length(var.dns_servers) == 0
}

resource "routeros_ip_dhcp_server" "self" {
  comment                   = "${var.interface_name} DHCP Server"
  name                      = var.interface_name
  interface                 = var.interface_name
  address_pool              = routeros_ip_pool.self.name
  client_mac_limit          = 1
  conflict_detection        = false
  dynamic_lease_identifiers = "client-mac,client-id"
  lease_time                = "1d"
}

resource "routeros_ip_dhcp_server_lease" "self" {
  for_each    = { for _, lease in var.static_leases : lease.mac => lease }
  server      = routeros_ip_dhcp_server.self.name
  address     = each.value.address
  mac_address = each.value.mac
  comment     = each.value.name
}
