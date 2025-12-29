variable "bridge_name" {
  type        = string
  description = "Name of the main bridge interface"
}

variable "wan_interface" {
  type        = string
  description = "Name of the WAN interface"
}

variable "limit_rx" {
  type = string
}

variable "limit_tx" {
  type = string
}
