locals {
  units_path = find_in_parent_folders("tf-catalog/units")
  env_config = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  vlans = local.env_config.locals.vlans
}

unit "base" {
  source = "${local.units_path}/ros/base"
  path = "base"

  values = {
    lab_path = "../../../../../prd/ros-lab/.terragrunt-stack/ros-lab",
    hostname = "switch",

    ethernet_interfaces = {
      ether1 = { comment = "oom", bridge_port = false }
      ether2 = { comment = "router", bridge_port = true, tagged = [local.vlans.Management.name] }
    }

    oob_mgmt_interface = "ether1"
  }
}
