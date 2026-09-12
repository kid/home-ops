include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/tf-catalog/modules/incus-vlan-networks"
}

inputs = {
  # parent: node1's trunk NIC (modules/den/hosts/node1.nix, "10-trunk").
  # vlan_id: modules/den/clusters/prd.nix (K3s), modules/den/networks.nix
  # (Storage) — den.networks.K3s.vlanId / den.networks.Storage.vlanId.
  networks = {
    k3s = {
      parent  = "enp36s0f1"
      vlan_id = 40
    }
    storage = {
      parent  = "enp36s0f1"
      vlan_id = 20
    }
  }
}
