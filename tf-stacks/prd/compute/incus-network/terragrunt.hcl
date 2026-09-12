include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/tf-catalog/modules/incus-vlan-networks"
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
