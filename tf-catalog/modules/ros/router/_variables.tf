# vim: foldmethod=marker foldmarker={{{,}}}

variable "oob_mgmt_interface" {
  type        = string
  description = "The interface to use for out of band management"
}

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

variable "vlans_input_rules" {
  type = map(list(object({
    comment            = string
    action             = string
    out_interface      = optional(string)
    out_interface_list = optional(string)
  })))
  default = {}
}

variable "vlans_forward_rules" {
  type = map(list(object({
    comment            = string
    action             = string
    out_interface      = optional(string)
    out_interface_list = optional(string)
  })))
  default = {}
}

# }}}

variable "dhcp_servers" {
  type = map(object({
    cidr        = string
    domain      = string
    gateway     = optional(string)
    dhcp_pool   = optional(list(string))
    dns_servers = optional(list(string))
    static_leases = optional(list(object({
      name    = string
      mac     = string
      address = string
    })))
  }))
  default = {}
}

variable "dhcp_static_leases" {
  type = map(list(object({
    name    = string
    mac     = string
    address = string
  })))
  default = {}
}

# DNS Configuration {{{

variable "dns_upstream_servers" {
  type = list(string)
}

variable "dns_static_records" {
  type = map(object({
    type    = string
    address = string
    comment = optional(string)
  }))
  default = {}
}

# }}}
