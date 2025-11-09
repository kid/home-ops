variable "devices" {
  type = list(object({
    name = string
    type = string
    interfaces = list(object({
      name        = string
      type        = string # oob / port / wan
      mac_address = string
      ip_address  = optional(string)
      target      = optional(string)
    }))
  }))
}

variable "routeros_version" {
  type    = string
  default = "7.20.1"
}
