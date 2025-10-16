variable "devices" {
  type = list(object({
    name = string
    type = string
    interfaces = list(object({
      type   = string # wan or port
      target = optional(string)
    }))
  }))
}

variable "routeros_version" {
  type    = string
  default = "7.20.1"
}

variable "oob_network" {
  type    = string
  default = "192.168.89.0"
}

variable "oob_prefix" {
  type    = number
  default = 24
}

variable "ssh_username" {
  type = string
}

variable "ssh_password" {
  type      = string
  sensitive = true
}

variable "ssh_keys" {
  type = list(string)
}
