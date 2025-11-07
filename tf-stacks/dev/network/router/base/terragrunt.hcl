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

dependency "lab" {
  config_path = "../../../lab"

  mock_outputs = {
    oob_ips = {
      router = ""
      switch = ""
    }
  }
}

locals {
  hostname = "router"

  management_cidr   = include.root.locals.env_config.locals.management_vlan.cidr
  management_prefix = split("/", local.management_cidr)[1]
  management_vlan = merge(include.root.locals.env_config.locals.management_vlan, {
    ip_address = "${cidrhost(local.management_cidr, 1)}/${local.management_prefix}"
  })

  vlans = {
    for name, vlan in include.root.locals.env_config.locals.vlans :
    name => merge({ ip_address = "${cidrhost(vlan.cidr, 1)}/${vlan.prefix}" }, vlan)
  }
}

inputs = merge(
  include.root.inputs,
  {
    routeros_endpoint     = run_cmd("../../get_ros_endpoint.sh", dependency.lab.outputs.oob_ips[local.hostname]),
    certificate_alt_names = ["IP:${dependency.lab.outputs.oob_ips[local.hostname]}"],

    oob_mgmt_ip_address = "${dependency.lab.outputs.oob_ips[local.hostname]}/24"

    hostname = local.hostname

    management_vlan = local.management_vlan
    vlans           = local.vlans

    ethernet_interfaces = {
      ether1 = { comment = "oom", bridge_port = false }
      ether2 = { comment = "wan", bridge_port = false }
      ether3 = { comment = "switch", bridge_port = true, tagged = [local.management_vlan.name] }
      ether4 = { comment = "trusted1", bridge_port = true, untagged = local.vlans.Trusted.name }
      ether5 = { comment = "guest1", bridge_port = true, untagged = local.vlans.Guest.name }
    }

    oob_mgmt_interface = "ether1"

    dhcp_clients = [{ interface = "ether2" }]
  },
)
