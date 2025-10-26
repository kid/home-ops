resource "routeros_interface_list" "wan" {
  name    = "WAN"
  comment = "All Public-Facing Interfaces"
}

resource "routeros_interface_list" "lan" {
  name    = "LAN"
  comment = "All Local Interfaces"
}

resource "routeros_interface_list_member" "wan" {
  list      = routeros_interface_list.wan.name
  interface = var.wan_interface
}

resource "routeros_interface_list_member" "lan_bridge" {
  list      = routeros_interface_list.lan.name
  interface = var.bridge_name
}

resource "routeros_interface_list_member" "lan_vlans" {
  for_each  = var.vlans
  list      = routeros_interface_list.lan.name
  interface = each.value.name
}
