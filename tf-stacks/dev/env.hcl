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
        { type = "port", target = "client1" },
      ]
    },
    {
      name = "switch"
      type = "chr"
      interfaces = [
        { type = "oob" },
        { type = "port", target = "router" },
      ]
    },
    {
      name = "client1"
      type = "chr"
      interfaces = [
        { type = "oob" },
        { type = "port", target = "router" },
      ]
    }
  ]

  vlans_tmp = [
    {
      vlan_id = 99
      prefix  = 16
      name    = "Management"
      domain  = "mgmt.${local.tld}"
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
      vlan_id = 100
      name    = "Lan"
      domain  = "lan.${local.tld}"
    },
    {
      vlan_id = 101
      name    = "Wlan"
      domain  = "wlan.${local.tld}"
    },    {
      vlan_id = 110
      name    = "Guest"
      domain  = "guest.${local.tld}"
    },
  ]

  vlans = { for _, vlan in local.vlans_tmp :
    vlan.name => merge(vlan, {
      cidr = cidrsubnet(local.env_cidr, try(vlan.prefix, 24) - local.env_cidr_prefix, vlan.vlan_id)
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
  certificate_unit   = "lab"
  oob_mgmt_interface = "ether1"

  devices   = local.devices
  vlans     = local.vlans
  users     = local.users
  passwords = local.passwords
}
