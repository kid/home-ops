variable "vlans" {
  type = map(object({
    name        = string
    vlan_id     = number
    cidr        = string
    domain      = string
    mtu         = optional(number, 1500)
    dhcp_client = optional(bool, false)
    dhcp_server = optional(object({
      gateway     = optional(string)
      dhcp_pool   = optional(list(string))
      dns_servers = optional(list(string))
    }), {})
  }))
  default = {}
}
