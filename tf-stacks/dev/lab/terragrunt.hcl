locals {
  devices = read_terragrunt_config("./devices.hcl").locals.devices
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
  include.root.locals.proxmox_inputs,
  {
    routeros_endpoint     = "https://10.99.0.1"
    routeros_secrets_path = "${get_repo_root()}/secrets/prd/routeros.sops.yaml"
    routeros_version      = "7.21beta5"
    devices               = local.devices
  },
)
