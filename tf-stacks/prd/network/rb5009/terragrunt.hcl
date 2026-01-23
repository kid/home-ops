include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

include "provider_routeros" {
  path = "${get_repo_root()}/tf-catalog/modules/_shared/provider-routeros.hcl"
}

terraform {
  source                   = "${get_repo_root()}/tf-catalog/modules/ros//base"
  copy_terraform_lock_file = false
}

locals {
  interface_lists = include.root.locals.env_config.locals.interface_lists
  vlans           = include.root.locals.env_config.locals.vlans
  all_vlans       = [for _, vlan in local.vlans : vlan.vlan_id]
  oob_port        = "ether7"
  wan_port        = "ether8"
}

inputs = merge(
  include.root.locals.base_inputs,
  {
    hostname          = "rb5009"
    routeros_endpoint = "10.99.0.1"

    certificate_alt_names = [
      "DNS:rb5009",
      "DNS:rb5009.kidibox.net",
      "IP:10.99.0.1",
      "IP:192.168.88.1",
    ]

    ntp_server_enabled = true

    vlans = local.vlans

    ethernet_interfaces = {
      sfp-sfpplus1 = {
        comment = "uplink to crs320"
        tagged  = local.all_vlans
      }
      ether1              = { comment = "pve1", tagged = local.all_vlans }
      ether2              = { comment = "switch", untagged = local.vlans.Management.vlan_id }
      ether3              = { comment = "capxr1", tagged = local.all_vlans }
      ether4              = { comment = "capxr0", tagged = local.all_vlans }
      "${local.oob_port}" = { comment = "oob", bridge_port = false, interface_lists = [local.interface_lists.MANAGEMENT] }
      "${local.wan_port}" = { comment = "wan", bridge_port = false, interface_lists = [local.interface_lists.WAN] }
    }

    ip_addresses = merge(
      {
        "${local.oob_port}" = "192.168.88.1/24"
        "${local.wan_port}" = "192.168.100.2/24"
      },
      {
        for _, vlan in local.vlans : vlan.name => "${cidrhost(vlan.cidr, 1)}/${vlan.prefix}"
      }
    )

    dhcp_clients = [{ interface = local.wan_port }]
    dhcp_servers = merge(
      {
        "${local.oob_port}" = {
          cidr        = "192.168.88.0/24"
          gateway     = null
          dns_servers = []
        }
      },
      {
        for name, vlan in local.vlans : name => merge(vlan, {
          gateway     = lookup(vlan, "dhcp_gateway", cidrhost(vlan.cidr, 1))
          dns_servers = lookup(vlan, "dhcp_dns_servers", [cidrhost(vlan.cidr, 1)])
        }) if lookup(vlan, "dhcp", true)
      },
    )

    dhcp_static_leases = {
      "${local.vlans.Management.name}" = [
        {
          name    = "crs320"
          mac     = "f4:1e:57:d1:75:94"
          address = cidrhost(local.vlans.Management.cidr, 2)
        },
        {
          name    = "capxr0"
          mac     = "48:a9:8a:cc:6d:62"
          address = cidrhost(local.vlans.Management.cidr, 10)
        },
        {
          name    = "capxr1"
          mac     = "48:a9:8a:ba:2a:6e"
          address = cidrhost(local.vlans.Management.cidr, 11)
        },
        {
          name    = "pve0-ipmi"
          mac     = "d0:50:99:f7:ee:15"
          address = cidrhost(local.vlans.Management.cidr, (local.vlans.Servers.vlan_id * 256) + 10)
        },
        {
          name    = "pikvm"
          mac     = "dc:a6:32:06:69:9a"
          address = cidrhost(local.vlans.Management.cidr, (local.vlans.Servers.vlan_id * 256) + 11)
        },
      ]
      "${local.vlans.Servers.name}" = [
        {
          name    = "pve0"
          mac     = "a6:34:58:9f:98:09"
          address = cidrhost(local.vlans.Servers.cidr, 10)
        },
        {
          name    = "pve1"
          mac     = "be:4f:11:f4:ba:61",
          address = cidrhost(local.vlans.Servers.cidr, 11)
        },
        {
          name    = "homeassistant"
          mac     = "52:54:00:93:9b:8f"
          address = cidrhost(local.vlans.Servers.cidr, 101)
        },
      ]
      "${local.vlans.Media.name}" = [
        {
          name    = "cloudflared1"
          mac     = "bc:24:11:bf:d2:cb"
          address = cidrhost(local.vlans.Media.cidr, 11)
        },
        {
          name    = "truenas"
          mac     = "bc:24:11:9f:50:bf"
          address = cidrhost(local.vlans.Media.cidr, 126)
        },
      ]
      "${local.vlans.Trusted.name}" = [
        {
          name    = "everything-presence-lite-20b1c4"
          mac     = "08:d1:f9:20:b1:c4"
          address = cidrhost(local.vlans.Trusted.cidr, 108)
        },
        {
          name    = "prtsrv"
          mac     = "bc:24:11:42:5b:fc"
          address = cidrhost(local.vlans.Trusted.cidr, 137)
        },
        {
          name    = "shield"
          mac     = "48:b0:2d:18:ec:cd"
          address = cidrhost(local.vlans.Trusted.cidr, 212)
        },
      ]
      "${local.vlans.IotLocal.name}" = [
        {
          name    = "doorbell"
          mac     = "ec:71:db:26:a9:37"
          address = cidrhost(local.vlans.IotLocal.cidr, 10)
        },
        {
          name    = "litters camera"
          mac     = "e0:01:c7:e4:e0:f3"
          address = cidrhost(local.vlans.IotLocal.cidr, 11)
        },
        {
          name    = "LGwebOSTV"
          mac     = "f0:86:20:10:84:18"
          address = cidrhost(local.vlans.IotLocal.cidr, 20)
        },
        {
          name    = "denon"
          mac     = "00:06:78:40:24:0a"
          address = cidrhost(local.vlans.IotLocal.cidr, 21)
        },
        {
          name    = "Somfy Box"
          mac     = "88:12:ac:04:36:44"
          address = cidrhost(local.vlans.IotLocal.cidr, 30)
        },
      ]
      "${local.vlans.IotInternet.name}" = [
        {
          name    = "roborock-vacuum-a38"
          mac     = "b0:4a:39:98:1c:cb"
          address = cidrhost(local.vlans.IotInternet.cidr, 30)
        },
        {
          name    = "dreame_vacuum_r2465a"
          mac     = "70:c9:32:4e:21:7d"
          address = cidrhost(local.vlans.IotInternet.cidr, 31)
        },
      ]
    }
  },
)
