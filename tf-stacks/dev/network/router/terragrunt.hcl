locals {
  hostname     = "router"
  vlans        = include.root.locals.env_config.locals.vlans
  vlans_prefix = { for name, vlan in local.vlans : name => tonumber(split("/", vlan.cidr)[1]) }
}

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
    routeros_endpoint     = run_cmd("../get_ros_endpoint.sh", dependency.lab.outputs.oob_ips[local.hostname]),
    certificate_alt_names = ["IP:${dependency.lab.outputs.oob_ips[local.hostname]}"],

    oob_mgmt_ip_address = "${dependency.lab.outputs.oob_ips[local.hostname]}/24"

    hostname = local.hostname

    ethernet_interfaces = {
      ether1 = { comment = "oom", bridge_port = false }
      ether2 = { comment = "wan", bridge_port = false }
      ether3 = { comment = "switch", bridge_port = true, tagged = [local.vlans.Management.name] }
      ether4 = { comment = "vm1", bridge_port = true, untagged = local.vlans.Trusted.name }
    }

    oob_mgmt_interface = "ether1"

    dhcp_clients = [{ interface = "ether2" }]

    ip_addresses = { for key, vlan in local.vlans :
      key => "${cidrhost(local.vlans[key].cidr, 1)}/${local.vlans_prefix[key]}"
    }
  },
)
