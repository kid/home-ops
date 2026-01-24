include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

include "provider_routeros" {
  path   = "${get_repo_root()}/tf-catalog/modules/_shared/provider-routeros.hcl"
  expose = true
}

terraform {
  source                   = "${get_repo_root()}/tf-catalog//modules/ros/firewall"
  copy_terraform_lock_file = false
}

dependencies {
  paths = [".."]
}

locals {
  interface_lists = include.root.locals.env_config.locals.interface_lists
  vlans           = include.root.locals.base_inputs.vlans
}

inputs = merge(
  include.root.locals.routeros_inputs,
  {
    mgmt_interface_list = local.interface_lists.MANAGEMENT
    wan_interface_list  = local.interface_lists.WAN

    vlans = local.vlans

    vlans_input_rules = {
      "${local.vlans.Trusted.name}" = [
        { action = "accept", dst_address = cidrhost(local.vlans.Management.cidr, 1), comment = "Allow access to Management from Trusted" },
      ]
      "${local.vlans.Talos.name}" = [
        { action = "accept", dst_port = "179", protocol = "tcp", comment = "Allow BGP from Talos" },
      ]
    }

    vlans_forward_rules = {
      "${local.vlans.Management.name}" = [
        { action = "accept", out_interface_list = "WAN", comment = "Allow WAN from Management" },
      ]
      "${local.vlans.Trusted.name}" = [
        { action = "accept", out_interface_list = "WAN", comment = "Allow WAN from Trusted" },
        { action = "accept", out_interface = local.vlans.Management.name, comment = "Allow access to Management from Trusted" },
        { action = "accept", out_interface_list = "all", comment = "Allow access to all vlans" },
      ]
      "${local.vlans.Guest.name}" = [
        { action = "accept", out_interface_list = "WAN", comment = "Allow WAN from Guest" },
      ]
      "${local.vlans.Talos.name}" = [
        { action = "accept", out_interface_list = "WAN", comment = "Allow WAN from Talos" },
      ]
    }
  },
)
