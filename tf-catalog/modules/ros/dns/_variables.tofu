# DNS Configuration {{{

variable "dns_upstream_servers" {
  type = list(string)
}

variable "dns_static_records" {
  type = map(object({
    address  = string
    type     = optional(string, "A")
    comment  = optional(string)
    disabled = optional(bool, false)
  }))
  default = {}
}

# }}}
