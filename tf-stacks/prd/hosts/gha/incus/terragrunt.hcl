include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/tf-catalog/modules//incus-nixos-vm"
}

generate "incus_provider" {
  path      = "incus_provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
provider "incus" {
  default_remote = "node0"

  remote {
    name    = "node0"
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
  address    = "10.0.30.10"
  bridge     = "ci-prd"
  cpu        = 4
  disk_size  = "100GiB"
  mac        = "52:54:00:30:00:01"
  memory     = "6GiB"
  name       = "gha"
  nixos_attr = "gha"
  remote     = "node0"
  ssh_authorized_keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAcnmLrPeTJeKsasfU0qn4sP4lBNeOUgRG4iZDS8nyEo kid@vulkan",
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHIM3nsk3HxvEcplSqwynh9V2NzlYdI10mrR746SiJZb kid@fw13",
  ]
  storage_pool = "default"
}
