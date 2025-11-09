include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

include "provider_routeros" {
  path = "${get_repo_root()}/tf-catalog/modules/_shared/provider-routeros.hcl"
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
  hostname        = "router"
  interface_lists = include.root.locals.env_config.locals.interface_lists

  vlans = {
    for name, vlan in include.root.locals.env_config.locals.vlans :
    name => merge({ ip_address = "${cidrhost(vlan.cidr, 1)}/${vlan.prefix}" }, vlan)
  }

  all_vlans = keys(local.vlans)
}

inputs = merge(
  include.root.locals.routeros_inputs,
  include.root.locals.env_config.inputs,
  {
    hostname              = local.hostname
    routeros_endpoint     = dependency.lab.outputs.oob_ips[local.hostname],
    certificate_alt_names = ["IP:${dependency.lab.outputs.oob_ips[local.hostname]}"],

    vlans = local.vlans

    ethernet_interfaces = {
      ether1 = { comment = "oob", bridge_port = false, interface_lists = [local.interface_lists.MANAGEMENT], ip_address = "${dependency.lab.outputs.oob_ips[local.hostname]}/24" }
      ether2 = { comment = "wan", bridge_port = false, interface_lists = [local.interface_lists.WAN] }
      ether3 = { comment = "switch", bridge_port = true, tagged = local.all_vlans }
      ether4 = { comment = "trusted1", bridge_port = true, untagged = local.vlans.Trusted.name }
      ether5 = { comment = "guest1", bridge_port = true, untagged = local.vlans.Guest.name }
    }

    dhcp_clients = [{ interface = "ether2" }]
  },
)
