resource "routeros_ip_firewall_nat" "wan" {
  comment            = "WAN Masquerade"
  chain              = "srcnat"
  action             = "masquerade"
  out_interface_list = var.wan_interface_list
}
