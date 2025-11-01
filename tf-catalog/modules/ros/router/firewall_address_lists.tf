locals {
  no_forward_ipv4_ranges = [
    {
      comment = "RFC6890"
      address = "0.0.0.0/8"
    },
    {
      comment = "RFC6890"
      address = "169.254.0.0/16"
    },
    {
      comment = "RFC6890: reserved"
      address = "240.0.0.0/4"
    },
    {
      comment = "RFC6890: limited broadcast"
      address = "255.255.255.255"
    },
  ]
}

resource "routeros_ip_firewall_addr_list" "no_forward_ipv4" {
  for_each = { for _, item in local.no_forward_ipv4_ranges : item.address => item }
  list     = "no_forward_ipv4"
  address  = each.value.address
  comment  = try(each.value.comment, null)
}
