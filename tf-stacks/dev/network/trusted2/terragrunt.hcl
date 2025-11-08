include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

include "provider_routeros" {
  path   = "${get_repo_root()}/tf-catalog/modules/_shared/provider-routeros.hcl"
  expose = true
}

terraform {
  source = "${get_repo_root()}/tf-catalog/modules/ros//base"

  before_hook "pre_destroy" {
    commands = ["destroy"]
    execute  = [find_in_parent_folders("hook_pre_destroy.sh")]
  }
}

dependencies {
  paths = ["../router", "../switch"]
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

locals {
  hostname        = "trusted2"
  interface_lists = include.root.locals.env_config.locals.interface_lists
}

inputs = merge(
  include.root.inputs,
  {
    hostname              = local.hostname
    routeros_endpoint     = run_cmd("../get_ros_endpoint.sh", dependency.lab.outputs.oob_ips[local.hostname]),
    certificate_alt_names = ["IP:${dependency.lab.outputs.oob_ips[local.hostname]}"],

    ethernet_interfaces = {
      ether1 = { comment = "oob", bridge_port = false, interface_lists = [local.interface_lists.MANAGEMENT], ip_address = "${dependency.lab.outputs.oob_ips[local.hostname]}/24" }
    }

    vlans = {}

    dhcp_clients = [{ interface = "ether2" }]
  },
)
