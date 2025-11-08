locals {
  routeros_secrets = yamldecode(sops_decrypt_file("${get_repo_root()}/secrets/routeros.sops.yaml"))

  environment = "dev"
  tld         = "${local.environment}.kidibox.net"

  env_cidr         = cidrsubnet("10.0.0.0/8", 1, 1)
  env_cidr_network = split("/", local.env_cidr)
  env_cidr_prefix  = tonumber(split("/", local.env_cidr)[1])

  devices = [
    {
      name = "router"
      type = "chr"
      interfaces = [
        { type = "oob" },
        { type = "wan" },
        { type = "port", target = "switch" },
        { type = "port", target = "trusted1" },
        { type = "port", target = "guest1" },
      ]
    },
    {
      name = "switch"
      type = "chr"
      interfaces = [
        { type = "oob" },
        { type = "port", target = "router" },
        { type = "port", target = "trusted2" },
        { type = "port", target = "guest2" },
      ]
    },
    {
      name = "trusted1"
      type = "chr"
      interfaces = [
        { type = "oob" },
        { type = "port", target = "router" },
      ]
    },
    {
      name = "guest1"
      type = "chr"
      interfaces = [
        { type = "oob" },
        { type = "port", target = "router" },
      ]
    },
    {
      name = "trusted2"
      type = "chr"
      interfaces = [
        { type = "oob" },
        { type = "port", target = "switch" },
      ]
    },
    {
      name = "guest2"
      type = "chr"
      interfaces = [
        { type = "oob" },
        { type = "port", target = "switch" },
      ]
    }
  ]

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
      vlan_id = 40
      name    = "Talos"
      domain  = "talos.${local.tld}"
    },
    {
      vlan_id = 42
      name    = "TalosSvc"
      domain  = "talos-svc.${local.tld}"
      dhcp    = false
    },
    {
      vlan_id = 100
      name    = "Trusted"
      domain  = "trusted.${local.tld}"
    },
    {
      vlan_id = 110
      name    = "Guest"
      domain  = "guest.${local.tld}"
    },
  ]

  vlans = { for _, vlan in local.vlans_array :
    vlan.name => merge(vlan, {
      prefix = try(vlan.prefix, 24)
      cidr   = cidrsubnet(local.env_cidr, try(vlan.prefix, 24) - local.env_cidr_prefix, vlan.vlan_id)
    })
  }

  users = { for name, user in local.routeros_secrets.users :
    name => {
      group = user.group
      keys  = user.ssh_keys
    }
  }

  passwords = { for name, user in local.routeros_secrets.users : name => user.password }
}

inputs = {
  certificate_unit = "lab"

  wan_interface_list  = local.interface_lists.WAN
  mgmt_interface_list = local.interface_lists.MANAGEMENT

  devices   = local.devices
  vlans     = local.vlans
  users     = local.users
  passwords = local.passwords
}
