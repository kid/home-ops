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
