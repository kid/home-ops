resource "routeros_ip_address" "oob" {
  address   = var.oob_mgmt_ip_address
  interface = var.oob_mgmt_interface
}

# TODO: should be templated from the unit / stack or executed as a hook?
import {
  to = routeros_ip_address.oob
  id = "*2"
}
