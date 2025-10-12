include "root" {
  path = find_in_parent_folders("root.hcl")
  expose = true
}

include "provider_proxmox" {
  path = "${get_repo_root()}/tf-catalog/modules/_shared/provider-proxmox.hcl"
  expose = true
}

include "provider_routeros" {
  path = "${get_repo_root()}/tf-catalog/modules/_shared/provider-routeros.hcl"
  expose = true
}

terraform {
  source = "${get_repo_root()}/tf-catalog/modules/proxmox//ros-lab"
}

inputs = merge(
  include.root.inputs,
  # include.provider_ros.inputs,
  # {
  #   ros_endpoint = "${local.scheme}://${values.ip_address}",
  # },
  values
)
