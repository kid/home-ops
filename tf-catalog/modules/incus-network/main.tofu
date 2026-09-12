# NAT'd Incus-managed bridge, for environments with no real VLAN to attach
# to (e.g. dev — see tf-stacks/dev/compute/incus-network). Not used by prd:
# node1's K3s VLAN bridge is NixOS-managed, not Terraform-managed (see
# tf-stacks/prd/compute/incus-network).

terraform {
  required_providers {
    incus = {
      source  = "lxc/incus"
      version = "~> 1.0"
    }
  }
}

variable "name" {
  description = "Incus network name."
  type        = string
}

variable "ipv4_address" {
  description = "Bridge IPv4 address/prefix (Incus `ipv4.address` config)."
  type        = string
}

resource "incus_network" "this" {
  name = var.name
  type = "bridge"

  config = {
    "ipv4.address" = var.ipv4_address
    "ipv4.nat"     = "true"
    "ipv6.address" = "none"
  }
}

output "network_name" {
  value = incus_network.this.name
}
