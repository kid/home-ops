include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/tf-catalog/modules/incus-k3s"
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

dependency "network" {
  config_path = "../incus-network"

  mock_outputs                            = { network_names = { k3s = "k3s-prd" } }
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

  network_name = dependency.network.outputs.network_names.k3s
  storage_pool = "default"
}
