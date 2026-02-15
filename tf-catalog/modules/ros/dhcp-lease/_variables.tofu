# vim: foldmethod=marker foldmarker={{{,}}}

# DHCP lease configuration {{{

variable "lease" {
  description = "Single DHCP lease to create"
  type = object({
    name     = string
    mac      = string
    address  = string
    comment  = optional(string)
    disabled = optional(bool, false)
  })
}

variable "dhcp_server" {
  description = "RouterOS DHCP server name for static leases"
  type        = string
  default     = null
}

variable "dns_zone" {
  description = "DNS zone to append to lease names"
  type        = string
  default     = null
}

variable "records" {
  description = "List of DNS records to create"
  type = list(object({
    name     = string
    address  = string
    type     = optional(string, "A")
    comment  = optional(string)
    disabled = optional(bool, false)
  }))
  default = []
}

# }}}
