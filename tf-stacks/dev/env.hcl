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

  vlans_tmp = [
    { id = 99, name = "Management", prefix = 16, domain = "mgmt.${local.tld}" },
    { id = 100, name = "Trusted", domain = "trusted.${local.tld}" },
  ]

  vlans = { for _, vlan in local.vlans_tmp :
    vlan.name => {
      name    = vlan.name
      domain  = vlan.domain
      vlan_id = vlan.id
      cidr    = cidrsubnet(local.env_cidr, try(vlan.prefix, 24) - local.env_cidr_prefix, vlan.id)
    }
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

  devices   = local.devices
  vlans     = local.vlans
  users     = local.users
  passwords = local.passwords
}
