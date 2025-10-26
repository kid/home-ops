locals {
  routeros_inputs = yamldecode(sops_decrypt_file("${get_repo_root()}/secrets/prd/routeros.sops.yaml"))
}

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

include "provider_proxmox" {
  path = "${get_repo_root()}/tf-catalog/modules/_shared/provider-proxmox.hcl"
}

include "provider_routeros" {
  path = "${get_repo_root()}/tf-catalog/modules/_shared/provider-routeros.hcl"
}

terraform {
  source = "${get_repo_root()}/tf-catalog/modules/proxmox//ros-lab"
}

inputs = merge(
  include.root.inputs,
  local.routeros_inputs["rb5009"],
  {
    routeros_version = "7.21beta3"
    ssh_username     = "kid"
    ssh_password     = "foobar"
    ssh_keys         = [file("~/.ssh/id_ed25519.pub")]
  },
)
