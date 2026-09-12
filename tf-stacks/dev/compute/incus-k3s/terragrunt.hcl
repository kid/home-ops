include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/tf-catalog/modules/incus-k3s"
}

dependency "network" {
  config_path = "../incus-network"

  # Lets `plan` succeed before incus-network has ever been applied.
  mock_outputs                            = { network_name = "k3s-dev" }
  mock_outputs_allowed_terraform_commands = ["init", "plan"]
}

inputs = {
  nodes = {
    k3s-dev-0 = {
      nixos_attr = "k3s-dev-0"
      cpu        = 2
      memory     = "4GiB"
      disk_size  = "20GiB"
    }
  }

  network_name = dependency.network.outputs.network_name
  storage_pool = "default"
}
