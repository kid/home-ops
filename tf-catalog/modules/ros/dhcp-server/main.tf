locals {
  cidr = "${var.cidr_network}/${var.cidr_prefix}"
}

resource "routeros_ip_pool" "self" {
  comment = "${var.interface_name} DHCP Pool"
  name    = "${var.interface_name}-dhcp-pool"
  ranges  = var.dhcp_ranges
}

resource "routeros_ip_dhcp_server_network" "self" {
  comment    = "${var.interface_name} DHCP Network"
  address    = local.cidr
  domain     = var.domain
  gateway    = var.gateway
  dns_server = var.dns_servers
}

resource "routeros_ip_dhcp_server" "self" {
  comment            = "${var.interface_name} DHCP Server"
  name               = var.interface_name
  interface          = var.interface_name
  address_pool       = routeros_ip_pool.self.name
  client_mac_limit   = 1
  conflict_detection = false
}

resource "routeros_ip_dhcp_server_lease" "self" {
  for_each    = var.static_leases
  server      = routeros_ip_dhcp_server.self.name
  address     = each.key
  mac_address = each.value.mac
  comment     = each.value.name
}
