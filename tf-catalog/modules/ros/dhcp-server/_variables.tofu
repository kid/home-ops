variable "interface_name" {
  description = "Name of the interface the DHCP server is bound to"
  type        = string
}

variable "cidr" {
  description = "Network in CIDR notation (e.g., 192.168.1.0/24)"
  type        = string
}

variable "gateway" {
  description = "Gateway IP address for the network"
  type        = string
}

variable "dhcp_ranges" {
  description = "List of IP ranges for DHCP pool (e.g., [\"192.168.1.100-192.168.1.200\"])"
  type        = list(string)
  default     = null
}

variable "ntp_servers" {
  description = "List of NTP servers to provide via DHCP"
  type        = list(string)
  default     = null
}

variable "dns_servers" {
  description = "List of DNS servers to provide via DHCP"
  type        = list(string)
  default     = null
}

variable "domain" {
  description = "Domain name to provide via DHCP"
  type        = string
  default     = null
}

variable "static_leases" {
  description = "Map of static DHCP leases with MAC address and IP address"
  type = list(object({
    address = string
    mac     = string
    name    = string
  }))
  default = []
}
