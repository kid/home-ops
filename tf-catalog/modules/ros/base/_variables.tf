# vim: foldmethod=marker foldmarker={{{,}}}

# Device settings {{{

variable "hostname" {
  type        = string
  description = "The name to assign to this device"
}

variable "timezone" {
  type        = string
  default     = "Europe/Brussels"
  description = "The timezone to set on the device"
}

variable "ntp_servers" {
  type        = list(string)
  default     = ["time.cloudflare.com"]
  description = "List of NTP servers to use."
}

# }}}

# Certificate details {{{

variable "certificate_alt_names" {
  type        = list(string)
  default     = []
  description = "Alternative names for the device certificate."
}

variable "certificate_country" {
  type        = string
  default     = "BE"
  description = "Country code for the device certificate."
}

variable "certificate_locality" {
  type        = string
  default     = "BRU"
  description = "Locality for the device certificate."
}

variable "certificate_organization" {
  type        = string
  default     = "kidibox.net"
  description = "Organization for the device certificate."
}

variable "certificate_unit" {
  type        = string
  default     = "home"
  description = "Organizational unit for the device certificate."
}

# }}}

# Management settings {{{

variable "mac_server_interfaces" {
  type        = string
  default     = "all"
  description = "Interface list to allow MAC server access on."
}

variable "oob_mgmt_interface" {
  type        = string
  description = "The interface to use for out of band management"
}

variable "oob_mgmt_ip_address" {
  type        = string
  description = "The ip address to use for out of band management"
}

# }}}

# Bridge settings {{{

variable "bridge_name" {
  type        = string
  default     = "bridge"
  description = "Name of the main bridge interface"
}

variable "bridge_comment" {
  type        = string
  default     = ""
  description = "Comment for the bridge interface"
}

variable "bridge_mtu" {
  type        = number
  default     = 1514
  description = "MTU for the bridge interface"
}

# }}}

# Interface configuration {{{

variable "ethernet_interfaces" {
  type = map(object({
    comment     = optional(string, "")
    bridge_port = optional(bool, true)
    mtu         = optional(number, 1500)
    l2mtu       = optional(number, 1518)

    # VLAN configuration
    tagged   = optional(list(string), [])
    untagged = optional(string)
  }))
  default     = {}
  description = "Map of ethernet interfaces to configure"
}

# }}}

# VLAN Configuration {{{

variable "vlans" {
  type = map(object({
    name         = string
    vlan_id      = number
    cidr_network = string
    cidr_prefix  = number
    mtu          = optional(number, 1500)
  }))
  default = {}
}

# }}}

# IP Configuration {{{

variable "dhcp_clients" {
  description = "List of interfaces to create DHCP client on"
  type = list(object({
    interface    = string
    use_peer_dns = optional(bool, true)
    use_peer_ntp = optional(bool, true)
  }))
  default = []
}

variable "ip_addresses" {
  description = "List of IP addresses to assign to interfaces"
  type        = map(string)
  default     = {}
}

# }}}

# Users configuration {{{

variable "users" {
  type = map(object({
    group   = string
    comment = optional(string)
    keys    = optional(list(string), [])
  }))
  default = {}
}

variable "passwords" {
  type      = map(string)
  sensitive = true
  default   = {}
}

# }}}
