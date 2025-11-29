resource "routeros_tool_mac_server" "self" {
  depends_on             = [routeros_interface_list.lists]
  allowed_interface_list = var.mgmt_interface_list
}

resource "routeros_tool_mac_server_winbox" "self" {
  depends_on             = [routeros_interface_list.lists]
  allowed_interface_list = var.mgmt_interface_list
}

resource "routeros_ip_neighbor_discovery_settings" "self" {
  depends_on              = [routeros_interface_list.lists]
  discover_interface_list = var.mgmt_interface_list
}

resource "routeros_tool_bandwidth_server" "self" {
  enabled = false
}
