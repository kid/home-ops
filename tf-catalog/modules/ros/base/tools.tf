# TODO: create a management interface list and set it here
# TODO: only allow neighbor discovery on the management interface list

resource "routeros_tool_mac_server" "self" {
  allowed_interface_list = var.mac_server_interfaces
}

resource "routeros_tool_mac_server_winbox" "self" {
  allowed_interface_list = var.mac_server_interfaces
}

resource "routeros_tool_bandwidth_server" "self" {
  enabled = false
}
