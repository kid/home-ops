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

variable "certificate_common_name" {
  type        = string
  description = "CN for the device certificate."
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

variable "mac_server_interfaces" {
  type        = string
  default     = "all"
  description = "Interface list to allow MAC server access on."
}

variable "ethernet_interfaces" {
  type = map(object({
    comment     = optional(string, "")
    bridge_port = optional(bool, true)

    tagged   = optional(list(string))
    untagged = optional(string)
  }))
  default     = {}
  description = "Map of ethernet interfaces to configure"
}

variable "bridge_name" {
  type = string
  default = "bridge"
  description = "Name of the main bridge interface"
}

variable "bridge_comment" {
  type = string
  default = ""
  description = "Comment for the bridge interface"
}
