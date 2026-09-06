terraform {
  required_providers {
    incus = {
      source  = "lxc/incus"
      version = "~> 1.0"
    }
  }
}

provider "incus" {}

resource "incus_network" "dev" {
  name = "incusbr0"
  type = "bridge"

  config = {
    "ipv4.address" = "10.150.19.1/24"
    "ipv4.nat"     = "true"
    "ipv6.address" = "none"
  }
}

output "network_name" {
  value = incus_network.dev.name
}
