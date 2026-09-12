terraform {
  required_providers {
    incus = {
      source  = "lxc/incus"
      version = "~> 1.0"
    }
  }
}

variable "networks" {
  description = "Incus bridge networks to create, each tagging one VLAN on a shared parent NIC via bridge.external_interfaces."
  type = map(object({
    name    = string
    parent  = string
    vlan_id = number
  }))
}

resource "incus_network" "this" {
  for_each = var.networks

  name = each.value.name
  type = "bridge"

  config = {
    "bridge.external_interfaces" = "vlan${each.value.vlan_id}/${each.value.parent}/${each.value.vlan_id}"
    "ipv4.address"               = "none"
    "ipv6.address"               = "none"
  }
}

output "network_names" {
  value = { for k, v in incus_network.this : k => v.name }
}
