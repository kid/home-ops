# One Incus `physical`-type network per VLAN, each tagging its own VLAN ID
# on a shared trunk NIC — Incus does the tagging itself, no host-side VLAN
# interface or bridge needed. Used by prd (node1's trunk carries both the
# K3s and Storage VLANs for Incus VMs) — see tf-stacks/prd/compute/
# incus-network. Unlike dev's incus-network module, there's no NAT/bridge
# here: these networks ride the VLANs that RouterOS already routes.

terraform {
  required_providers {
    incus = {
      source  = "lxc/incus"
      version = "~> 1.0"
    }
  }
}

variable "networks" {
  description = "Incus physical networks to create, keyed by name, each tagging one VLAN on a shared parent NIC."
  type = map(object({
    parent  = string
    vlan_id = number
  }))
}

resource "incus_network" "this" {
  for_each = var.networks

  name = each.key
  type = "physical"

  config = {
    parent = each.value.parent
    vlan   = tostring(each.value.vlan_id)
  }
}

output "network_names" {
  value = { for k, v in incus_network.this : k => v.name }
}
