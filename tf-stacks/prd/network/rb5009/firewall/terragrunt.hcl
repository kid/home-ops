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
  vlans           = include.root.locals.env_config.locals.vlans
}

inputs = merge(
  include.root.locals.base_inputs,
  {
    hostname          = "rb5009"
    routeros_endpoint = "10.99.0.1"

    vlans = { for name, vlan in local.vlans : name => vlan if lookup(vlan, "routed", true) }

    vlans_input_rules = {
      "${local.vlans.Trusted.name}" = [
        { action = "accept", dst_address = cidrhost(local.vlans.Management.cidr, 1), comment = "Allow access to Management from Trusted" },
      ]
      "${local.vlans.IotLocal.name}" = [
        { action = "accept", dst_address = cidrhost(local.vlans.IotLocal.cidr, 1), comment = "Allow access to NTP from IotLocal", dst_port = 123, protocol = "udp" },
      ]
    }

    vlans_forward_rules = {
      "${local.vlans.Management.name}" = [
        { action = "accept", out_interface_list = "WAN", comment = "Allow WAN from Management" },
      ]
      "${local.vlans.Servers.name}" = [
        { action = "accept", out_interface_list = "WAN", comment = "Allow WAN" },
        { action = "accept", out_interface_list = "all", comment = "Allow access to all vlans" }, # Because HomeAssistant lives here at the moment
      ]
      "${local.vlans.Media.name}" = [
        { action = "accept", out_interface_list = "WAN", comment = "Allow WAN" },
      ]
      "${local.vlans.Media.name}" = [
        { action = "accept", out_interface_list = "WAN", comment = "Allow WAN" },
        { action = "accept", dst_address = "10.0.10.101", src_address = "10.0.30.11", comment = "Allow cloudflared access to HomeAssistant" },
      ]
      "${local.vlans.IotLocal.name}" = [
        { action = "accept", out_interface_list = "WAN", comment = "Allow WAN", disabled = true },
      ]
      "${local.vlans.IotInternet.name}" = [
        { action = "accept", out_interface_list = "WAN", comment = "Allow WAN" },
      ]
      "${local.vlans.Trusted.name}" = [
        { action = "accept", out_interface_list = "WAN", comment = "Allow WAN" },
        { action = "accept", out_interface = local.vlans.Management.name, comment = "Allow access to Management" },
        { action = "accept", out_interface_list = "all", comment = "Allow access to all vlans" },
      ]
      "${local.vlans.Guest.name}" = [
        { action = "accept", out_interface_list = "WAN", comment = "Allow WAN" },
      ]
      "${local.vlans.RosLab.name}" = [
        { action = "accept", out_interface_list = "WAN", comment = "Allow WAN" },
      ]
    }
  },
)
