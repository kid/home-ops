resource "routeros_ip_dhcp_client" "self" {
  depends_on = [
    routeros_interface_ethernet.ethernet,
    routeros_interface_bridge.bridge,
  ]

  for_each     = { for _, item in var.dhcp_clients : item.interface => item }
  interface    = each.value.interface
  use_peer_dns = each.value.use_peer_dns
  use_peer_ntp = each.value.use_peer_ntp
}
