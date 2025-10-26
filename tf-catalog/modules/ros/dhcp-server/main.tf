data "routeros_ip_addresses" "self" {
  filter = {
    interface = var.interface_name
  }
}

locals {
  cidr          = "${var.cidr_network}/${var.cidr_prefix}"
  interface_ip  = split("/", data.routeros_ip_addresses.self.addresses[0].address)[0]
  default_range = "${cidrhost(local.cidr, 200)}-${cidrhost(local.cidr, 254)}"
}

resource "routeros_ip_pool" "self" {
  comment = "${var.interface_name} DHCP Pool"
  name    = "${var.interface_name}-dhcp-pool"
  ranges  = coalesce(var.dhcp_ranges, [local.default_range])
}

resource "routeros_ip_dhcp_server_network" "self" {
  comment    = "${var.interface_name} DHCP Network"
  address    = local.cidr
  domain     = var.domain
  gateway    = coalesce(var.gateway, local.interface_ip)
  dns_server = coalesce(var.dns_servers, [local.interface_ip])
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
