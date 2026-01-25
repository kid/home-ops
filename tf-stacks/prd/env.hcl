locals {
  environment = "prd"
  tld         = "home.kidibox.net"

  env_cidr         = cidrsubnet("10.0.0.0/8", 1, 0)
  env_cidr_network = split("/", local.env_cidr)
  env_cidr_prefix  = tonumber(split("/", local.env_cidr)[1])

  dns_upstream_servers = ["9.9.9.9", "149.112.112.112"]

  interface_lists = {
    MANAGEMENT = "MANAGEMENT"
    WAN        = "WAN"
  }

  vlans_array = [
    {
      vlan_id         = 99
      prefix          = 16
      name            = "Management"
      domain          = "mgmt.${local.tld}"
      interface_lists = [local.interface_lists.MANAGEMENT]
    },
    {
      vlan_id = 10
      name    = "Servers"
      domain  = "srv.${local.tld}"
    },
    {
      vlan_id = 20
      name    = "Storage"
      domain  = "storage.${local.tld}"
      mtu     = 9000
    },
    {
      vlan_id = 30
      name    = "Media"
      domain  = "media.${local.tld}"
    },
    {
      vlan_id = 40
      name    = "Talos"
      domain  = "talos.${local.tld}"
    },
    {
      vlan_id = 50
      name    = "IotLocal"
      domain  = "iot-local.${local.tld}"
    },
    {
      vlan_id          = 51
      name             = "IotInternet"
      domain           = "iot-internet.${local.tld}"
      dhcp_dns_servers = local.dns_upstream_servers
    },
    {
      vlan_id = 100
      name    = "Trusted"
      domain  = "lan.${local.tld}"
    },
    {
      vlan_id          = 101
      name             = "Guest"
      domain           = "iot.${local.tld}"
      dhcp_dns_servers = local.dns_upstream_servers
    },
    # {
    #   vlan_id = 110
    #   name    = "Guest"
    #   domain  = "guest.${local.tld}"
    # },
    {
      vlan_id = 1040
      name    = "LabTalos"
      routed  = false
    },
    {
      vlan_id = 1042
      name    = "LabTalosSvc"
      routed  = false
    },
    {
      vlan_id = 1100
      name    = "LabTrusted"
      routed  = false
    },
    {
      vlan_id          = 1991
      name             = "RosLab"
      cidr             = "192.168.89.0/24"
      dhcp_gateway     = "0.0.0.0"
      dhcp_dns_servers = []
    },
  ]

  vlans = merge(
    {
      for _, vlan in local.vlans_array :
      vlan.name => merge(vlan, {
        prefix = try(vlan.prefix, 24)
        cidr   = lookup(vlan, "cidr", cidrsubnet(local.env_cidr, try(vlan.prefix, 24) - local.env_cidr_prefix, vlan.vlan_id))
      })
      if lookup(vlan, "routed", true)
    },
    { for _, vlan in local.vlans_array : vlan.name => vlan if lookup(vlan, "routed", true) == false }
  )
}
