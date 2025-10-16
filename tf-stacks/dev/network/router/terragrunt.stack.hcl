locals {
  units_path = find_in_parent_folders("tf-catalog/units")
  env_config = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  vlans = local.env_config.locals.vlans
  lab_path = "../../../../../prd/ros-lab/.terragrunt-stack/ros-lab"
}

unit "base" {
  source = "${local.units_path}/ros/base"
  path = "base"

  values = {
    lab_path = local.lab_path
    hostname = "router"
    ethernet_interfaces = {
      ether1 = { comment = "oom", bridge_port = false }
      ether2 = { comment = "wan", bridge_port = false }
      ether3 = { comment = "switch", bridge_port = true, tagged = [local.vlans.Management.name] }
    }

    oob_mgmt_interface = "ether1"
  }
}

unit "router" {
  source = "${local.units_path}/ros/router"
  path = "router"

  values = {
    lab_path = local.lab_path
    hostname = "router"
  }
}
