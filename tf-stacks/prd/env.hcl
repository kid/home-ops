locals {
  environment = "prd"
  tld         = "home.kidibox.net"

  env_cidr         = cidrsubnet("10.0.0.0/8", 1, 0)
  env_cidr_network = split("/", local.env_cidr)
  env_cidr_prefix  = tonumber(split("/", local.env_cidr)[1])

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
    # {
    #   vlan_id = 42
    #   name    = "TalosSvc"
    #   domain  = "talos-svc.${local.tld}"
    #   dhcp    = false
    # },
    {
      vlan_id = 100
      name    = "Trusted"
      domain  = "lan.${local.tld}"
    },
    {
      vlan_id = 101
      name    = "Iot"
      domain  = "iot.${local.tld}"
    },
    # {
    #   vlan_id = 110
    #   name    = "Guest"
    #   domain  = "guest.${local.tld}"
    # },
    {
      vlan_id     = 1991
      name        = "RosLab"
      dhcp_routed = false
    },
  ]

  vlans = {
    for _, vlan in local.vlans_array :
    vlan.name => merge(vlan, {
      prefix = try(vlan.prefix, 24)
      cidr   = cidrsubnet(local.env_cidr, try(vlan.prefix, 24) - local.env_cidr_prefix, vlan.vlan_id)
    })
  }
}
