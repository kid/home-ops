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

dependencies {
  paths = [".."]
}

locals {
  vlans = include.root.locals.env_config.locals.vlans
}

inputs = merge(
  include.root.locals.base_inputs,
  {
    hostname           = "rb5009"
    routeros_endpoint  = "10.99.0.1"
    capsman_interfaces = [local.vlans.Management.name]

    passphrase_groups = {
      "${local.vlans.Trusted.name}" = {
        vlan_id = local.vlans.Trusted.vlan_id
      }
      "${local.vlans.Guest.name}" = {
        vlan_id  = local.vlans.Guest.vlan_id
        isolated = true
      }
      "${local.vlans.IotLocal.name}" = {
        vlan_id  = local.vlans.IotLocal.vlan_id
        isolated = true
      }
      "${local.vlans.IotInternet.name}" = {
        vlan_id  = local.vlans.IotInternet.vlan_id
        isolated = true
      }
    }
  },
)
