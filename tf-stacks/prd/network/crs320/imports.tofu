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

# import {
#   to = routeros_interface_vlan.vlans["Management"]
#   id = "name=vlan-mgmt"
# }

import {
  to = routeros_interface_ethernet.ethernet["ether17"]
  id = "name=ether17"
}

# import {
#   to = routeros_ip_address.addresses["ether17"]
#   id = "address=192.168.88.1/24"
# }
