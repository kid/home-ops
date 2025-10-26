# vim: foldmethod=marker foldmarker={{{,}}}

variable "wan_interface" {
  type = string
}

variable "bridge_name" {
  type        = string
  default     = "bridge"
  description = "Name of the main bridge interface"
}

# VLAN Configuration {{{

variable "vlans" {
  type = map(object({
    name        = string
    vlan_id     = number
    cidr        = string
    domain      = string
    mtu         = optional(number, 1500)
    gateway     = optional(string)
    dhcp_pool   = optional(list(string))
    dns_servers = optional(list(string))
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
