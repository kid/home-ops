# vim: foldmethod=marker foldmarker={{{,}}}

# Interface lists {{{

variable "mgmt_interface_list" {
  type        = string
  description = "The management interface list"
}

variable "wan_interface_list" {
  type = string
}

# }}}

# VLAN Configuration {{{

variable "vlans" {
  type = map(object({
    name    = string
    vlan_id = number
  }))
  default = {}
}

variable "vlans_input_rules" {
  type = map(list(object({
    comment            = string
    action             = string
    out_interface      = optional(string)
    out_interface_list = optional(string)
    src_address        = optional(string)
    src_address_list   = optional(string)
    dst_address        = optional(string)
    dst_address_list   = optional(string)
  })))
  default = {}
}

variable "vlans_forward_rules" {
  type = map(list(object({
    comment            = string
    action             = string
    out_interface      = optional(string)
    out_interface_list = optional(string)
    src_address        = optional(string)
    src_address_list   = optional(string)
    dst_address        = optional(string)
    dst_address_list   = optional(string)
  })))
  default = {}
}

# }}}
