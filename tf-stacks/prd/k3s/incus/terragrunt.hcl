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
    }
  EOF
}

inputs = {
  network = {
    name    = "k3s-prd"
    parent  = "enp36s0f1"
    vlan_id = 40
  }

  nodes = {
    k3s-prd-0 = {
      nixos_attr = "k3s-prd-0"
      cpu        = 4
      memory     = "8GiB"
      disk_size  = "40GiB"
      mac        = "52:54:00:40:00:01"
      extra_disks = {
        miroir-data = { size = "20GiB" }
      }
    }
  }

  storage_pool = "default"
}
