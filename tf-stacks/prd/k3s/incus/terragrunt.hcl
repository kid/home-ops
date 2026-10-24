include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/tf-catalog/modules//incus-k3s-vlan"
}

generate "incus_provider" {
  path      = "incus_provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
provider "incus" {
  default_remote = "node1"

  remote {
    name    = "node1"
    address = "https://10.0.10.10:8443"
  }

  remote {
    name     = "images"
    address  = "https://images.linuxcontainers.org"
    protocol = "simplestreams"
  }
}
EOF
}

inputs = {
  extra_networks = {
    storage = {
      mtu     = 9000
      name    = "storage-prd"
      parent  = "enp36s0f1"
      vlan_id = 20
    }
  }
  network = {
    name    = "k3s-prd"
    parent  = "enp36s0f1"
    vlan_id = 40
  }
  nodes = {
    k3s-prd-0 = {
      address   = "10.0.40.10"
      cpu       = 4
      disk_size = "64GiB"
      extra_nics = {
        storage = {
          mac = "52:54:00:20:00:01"
        }
      }
      mac        = "52:54:00:40:00:01"
      memory     = "16GiB"
      nixos_attr = "k3s-prd-0"
    }
    k3s-prd-1 = {
      address   = "10.0.40.11"
      cpu       = 4
      disk_size = "64GiB"
      extra_nics = {
        storage = {
          mac = "52:54:00:20:00:02"
        }
      }
      mac        = "52:54:00:40:00:02"
      memory     = "8GiB"
      nixos_attr = "k3s-prd-1"
    }
  }
  ssh_authorized_keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAcnmLrPeTJeKsasfU0qn4sP4lBNeOUgRG4iZDS8nyEo kid@vulkan",
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHIM3nsk3HxvEcplSqwynh9V2NzlYdI10mrR746SiJZb kid@fw13",
  ]
  storage_pool = "default"
}
