locals {
  routeros_secrets = yamldecode(sops_decrypt_file("${get_repo_root()}/secrets/routeros.sops.yaml"))

  environment = "dev"

  devices = [
    {
      name = "router"
      type = "chr"
      interfaces = [
        { type = "oob" },
        { type = "wan" },
        { type = "port", target = "switch" },
        { type = "port", target = "vm1" },
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
      name = "vm1"
      type = "debian"
      interfaces = [
        { type = "port", target = "router" },
      ]
    }
  ]

  vlans = {
    Management = {
      name         = "Management"
      vlan_id      = 99
      cidr_network = "10.227.0.0"
      cidr_prefix  = 16
      domain       = "mgmt.lab.kidibox.net"
    }
    Trusted = {
      name         = "Trusted"
      vlan_id      = 100
      cidr_network = "10.128.100.0"
      cidr_prefix  = 24
      domain       = "trusted.lab.kidibox.net"
    }
  }

  vlans_cidr = { for key, vlan in local.vlans : key => "${vlan.cidr_network}/${vlan.cidr_prefix}" }

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

  devices   = local.devices
  vlans     = local.vlans
  users     = local.users
  passwords = local.passwords
}
