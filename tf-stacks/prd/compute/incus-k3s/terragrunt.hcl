include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/tf-catalog/modules/incus-k3s"
}

dependency "network" {
  config_path = "../incus-network"

  mock_outputs                            = { network_names = { prd-k3s = "prd-k3s" } }
  mock_outputs_allowed_terraform_commands = ["init", "plan"]
}

inputs = {
  nodes = {
    k3s-prd-0 = {
      nixos_attr = "k3s-prd-0"
      cpu        = 4
      memory     = "8GiB"
      disk_size  = "40GiB"
      mac        = "52:54:00:40:00:01"
    }
  }

  network_name = dependency.network.outputs.network_names["prd-k3s"]
  storage_pool = "default"
}
