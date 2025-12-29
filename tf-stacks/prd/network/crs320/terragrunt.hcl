include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

include "provider_routeros" {
  path   = "${get_repo_root()}/tf-catalog/modules/_shared/provider-routeros.hcl"
  expose = true
}

terraform {
  source                   = "${get_repo_root()}/tf-catalog/modules/ros//base"
  copy_terraform_lock_file = false
}

# dependencies {
#   paths = ["../router"]
# }

locals {
  interface_lists = include.root.locals.env_config.locals.interface_lists
  vlans           = include.root.locals.base_inputs.vlans
}

inputs = merge(
  include.root.locals.base_inputs,
  {
    hostname          = "crs320"
    routeros_endpoint = "10.99.0.2"

    bridge_name = "bridge1"

    certificate_alt_names = [
      "DNS:crs320",
      "DNS:crs320.kidibox.net",
      "IP:10.99.0.2",
      "IP:192.168.88.1",
    ]

    vlans = {
      Management = local.vlans.Management
      # Management = merge(local.vlans.Management, {
      #   ip_address = "${cidrhost(local.vlans.Management.cidr, 2)}/${local.vlans.Management.prefix}"
      # })
    }

    ethernet_interfaces = {
      ether17 = { comment = "oob", bridge_port = false, interface_lists = [local.interface_lists.MANAGEMENT] }
      # ether1 = { tagged = [local.vlans.Management.vlan_id], untagged = 100 }
      # ether2 = { tagged = [local.vlans.Management.vlan_id] }
    }

    ip_addresses = {
      ether17 = "192.168.88.1/24"
      "${local.vlans.Management.name}" = "${cidrhost(local.vlans.Management.cidr, 2)}/${local.vlans.Management.prefix}"
    }

    dhcp_servers = {
      ether17 = {
        cidr        = "192.168.88.0/24"
        dns_servers = []
      }
    }
  },
)
