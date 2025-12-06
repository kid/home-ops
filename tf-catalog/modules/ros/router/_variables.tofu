# vim: foldmethod=marker foldmarker={{{,}}}

variable "mgmt_interface_list" {
  type        = string
  description = "The management interface list"
}

variable "wan_interface_list" {
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
    name       = string
    vlan_id    = number
    ip_address = optional(string, null)
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
