include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

include "provider_routeros" {
  path   = "${get_repo_root()}/tf-catalog/modules/_shared/provider-routeros.hcl"
  expose = true
}

terraform {
  source                   = "${get_repo_root()}/tf-catalog/modules/ros//capsman"
  copy_terraform_lock_file = false
}

locals {
  vlans = include.root.locals.base_inputs.vlans
}

inputs = merge(
  include.root.locals.base_inputs,
  {
    hostname           = "rb5009"
    routeros_endpoint  = "10.99.0.1"
    capsman_interfaces = ["adm"]
    # capsman_interfaces = [vlans.Management.name]
  },
)
