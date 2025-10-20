locals {
  hostname = "switch"
  vlans = include.root.locals.env_config.locals.vlans
  mgmt_cidr = "${local.vlans.Management.cidr_network}/${local.vlans.Management.cidr_prefix}"
}

include "root" {
  path = find_in_parent_folders("root.hcl")
  expose = true
}

include "provider_routeros" {
  path = "${get_repo_root()}/tf-catalog/modules/_shared/provider-routeros.hcl"
  expose = true
}

terraform {
  source = "${get_repo_root()}/tf-catalog/modules/ros//base"

  before_hook "pre_destroy" {
    commands = ["destroy"]
    execute  = ["../hook_pre_destroy.sh"]
  }
}

dependencies {
  paths = ["../router"]
} 

dependency "lab" {
  config_path = "../../lab"

  mock_outputs = {
    oob_ips = { 
      router = "" 
      switch = ""
    }
  }
}

inputs = merge(
  include.root.inputs,
  {
    routeros_endpoint = run_cmd("../get_ros_endpoint.sh", dependency.lab.outputs.oob_ips[local.hostname]),
    certificate_alt_names = ["IP:${dependency.lab.outputs.oob_ips[local.hostname]}"],

    oob_mgmt_ip_address = "${dependency.lab.outputs.oob_ips[local.hostname]}/24"

    hostname = local.hostname

    ethernet_interfaces = {
      ether1 = { comment = "oom", bridge_port = false }
      ether2 = { comment = "router", bridge_port = true, tagged = [local.vlans.Management.name] }
    }

    oob_mgmt_interface = "ether1"

    dhcp_clients = [{ interface = local.vlans.Management.name }]
  },
)
