# vim: foldmethod=marker foldmarker={{{,}}}

# VLAN Configuration {{{

variable "vlans" {
  type = map(object({
    name         = string
    vlan_id      = number
    cidr_network = string
    cidr_prefix  = number
    mtu          = optional(number, 1500)
    gateway      = optional(string)
    dhcp_pool    = optional(list(string))
    dns_servers  = optional(list(string))
    domain       = string
  }))
  default = {}
}

# }}}

variable "static_leases" {
  type = list(object({
    name    = string
    vlan    = string
    mac     = string
    address = string
  }))
  default = []
}
