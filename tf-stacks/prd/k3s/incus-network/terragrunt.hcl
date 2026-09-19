include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/tf-catalog/modules/incus-vlan-networks"
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
  networks = {
    k3s = {
      name    = "k3s-prd"
      parent  = "enp36s0f1"
      vlan_id = 40
    }
  }
}
