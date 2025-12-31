import {
  to = routeros_interface_bridge.bridge
  id = "*18"
}

import {
  to = routeros_system_identity.identity
  id = "."
}
import {
  to = routeros_tool_bandwidth_server.self
  id = "."
}
import {
  to = routeros_tool_mac_server.self
  id = "."
}
import {
  to = routeros_tool_mac_server_winbox.self
  id = "."
}

import {
  to = routeros_interface_vlan.vlans["Management"]
  id = "name=vlan-mgmt"
}

import {
  to = routeros_interface_list_member.lists_members["MANAGEMENT-Management"]
  id = "*4"
}

import {
  for_each = { for k, v in var.ethernet_interfaces : k => v if lookup(v, "bridge_port", true) }
  to       = routeros_interface_bridge_port.ethernet_ports[each.key]
  id       = "interface=${each.key}"
}
import {
  for_each = { for k, v in var.ethernet_interfaces : k => v if lookup(v, "bridge_port", true) }
  to       = routeros_interface_ethernet.ethernet[each.key]
  id       = "name=${each.key}"
}

import {
  to = routeros_interface_bridge_vlan.bridge_vlans["99"]
  id = "*5"
}
import {
  to = routeros_interface_bridge_vlan.bridge_vlans["10"]
  id = "*9"
}
import {
  to = routeros_interface_bridge_vlan.bridge_vlans["30"]
  id = "*8"
}
import {
  to = routeros_interface_bridge_vlan.bridge_vlans["100"]
  id = "*B"
}
import {
  to = routeros_interface_bridge_vlan.bridge_vlans["101"]
  id = "*A"
}
import {
  to = routeros_interface_bridge_vlan.bridge_vlans["1991"]
  id = "*133"
}





