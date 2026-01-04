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

dependencies {
  paths = ["../rb5009"]
}

locals {
  interface_lists = include.root.locals.env_config.locals.interface_lists
  vlans           = include.root.locals.env_config.locals.vlans
  all_vlans       = [for vlan in local.vlans : vlan.vlan_id]
}

inputs = merge(
  include.root.locals.base_inputs,
  {
    hostname          = "crs320"
    routeros_endpoint = "10.99.0.2"

    certificate_alt_names = [
      "DNS:crs320",
      "DNS:crs320.kidibox.net",
      "IP:10.99.0.2",
      "IP:192.168.88.1",
    ]

    vlans = {
      Management = local.vlans.Management
    }

    ethernet_interfaces = {
      sfp-sfpplus1 = {
        comment = "uplink to rb5009"
        tagged  = local.all_vlans
      }
      sfp-sfpplus3 = {
        comment = "pve0"
        tagged  = local.all_vlans
      }
      sfp-sfpplus4 = {
        comment = "pve1"
        tagged  = local.all_vlans
      }
      ether1 = {
        command  = "vulkan"
        untagged = local.vlans.Trusted.vlan_id
        tagged = [
          local.vlans.Management.vlan_id,
          local.vlans.RosLab.vlan_id,
        ]
      }
      ether2 = {
        command  = "rb5009"
        untagged = local.vlans.Management.vlan_id
      }
      ether7 = {
        comment = "capxr1"
        tagged  = local.all_vlans
      }
      ether9 = {
        comment = "capxr0"
        tagged  = local.all_vlans
      }
      ether10 = {
        comment  = "doorbell"
        untagged = local.vlans.IotLocal.vlan_id
      }
      ether11 = {
        comment  = "petdoor"
        untagged = local.vlans.IotInternet.vlan_id
      }
      ether14 = {
        comment  = "pve0-ipmi"
        untagged = local.vlans.Management.vlan_id
      }
      ether16 = {
        comment  = "pve1-ipmi"
        untagged = local.vlans.Management.vlan_id
      }
      ether17 = { comment = "oob", bridge_port = false, interface_lists = [local.interface_lists.MANAGEMENT] }
    }

    ip_addresses = {
      ether17                          = "192.168.88.1/24"
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
