include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source                   = "git::git@github.com:kid/terragrunt-infra-catalog//modules/ros-base?ref=feat/onepassword-secrets"
  copy_terraform_lock_file = false
}

dependencies {
  paths = [
    "../rb5009",
  ]
}

inputs = {
  bridge_name = "bridge1"
  certificate_alt_names = [
    "DNS:crs320",
    "DNS:crs320.kidibox.net",
    "IP:10.99.0.2",
    "IP:192.168.88.1",
  ]
  dhcp_servers = {
    ether17 = {
      cidr        = "192.168.88.0/24"
      dns_servers = []
    }
  }
  dns_upstream_servers = [
    "9.9.9.9",
    "149.112.112.112",
  ]
  ethernet_interfaces = {
    ether1 = {
      command = "vulkan"
      tagged = [
        99,
        40,
        1991,
        1040,
        1042,
        1100,
      ]
      untagged = 100
    }
    ether10 = {
      comment  = "doorbell"
      untagged = 50
    }
    ether11 = {
      comment  = "petdoor"
      untagged = 51
    }
    ether14 = {
      comment  = "pve0-ipmi"
      untagged = 99
    }
    ether16 = {
      comment  = "pve1-ipmi"
      untagged = 99
    }
    ether17 = {
      bridge_port = false
      comment     = "oob"
      interface_lists = [
        "MANAGEMENT",
      ]
    }
    ether2 = {
      comment  = "rb5009"
      untagged = 99
    }
    ether7 = {
      comment = "capxr1"
      tagged = [
        101,
        51,
        50,
        40,
        1040,
        1042,
        1100,
        99,
        30,
        1991,
        10,
        20,
        100,
      ]
    }
    ether9 = {
      comment = "capxr0"
      tagged = [
        101,
        51,
        50,
        40,
        1040,
        1042,
        1100,
        99,
        30,
        1991,
        10,
        20,
        100,
      ]
    }
    sfp-sfpplus1 = {
      comment = "uplink to rb5009"
      tagged = [
        101,
        51,
        50,
        40,
        1040,
        1042,
        1100,
        99,
        30,
        1991,
        10,
        20,
        100,
      ]
    }
    sfp-sfpplus3 = {
      comment  = "pve0"
      untagged = 40
    }
    sfp-sfpplus4 = {
      comment = "pve1"
      tagged = [
        101,
        51,
        50,
        40,
        1040,
        1042,
        1100,
        99,
        30,
        1991,
        10,
        20,
        100,
      ]
    }
  }
  hostname = "crs320"
  ip_addresses = {
    Management = "10.99.0.2/16"
    ether17    = "192.168.88.1/24"
  }
  mgmt_interface_list = "MANAGEMENT"
  op_item_routeros    = "CRS320 - user - kid"
  op_vault            = "home-ops"
  routeros_endpoint   = "10.99.0.2"
  routeros_groups = {
    external-dns = {
      policies = [
        "api",
        "read",
        "rest-api",
        "write",
      ]
    }
    metrics = {
      policies = [
        "api",
        "read",
      ]
    }
  }
  routeros_users = {
    admin = {
      disabled = false
    }
    external-dns = {
      group = "external-dns"
    }
    kid = {
      group = "full"
      ssh_keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAcnmLrPeTJeKsasfU0qn4sP4lBNeOUgRG4iZDS8nyEo kid@vulkan",
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHIM3nsk3HxvEcplSqwynh9V2NzlYdI10mrR746SiJZb kid@fw13",
      ]
    }
    metrics = {
      group = "metrics"
    }
  }
  vlans = {
    Management = {
      interface_lists = [
        "MANAGEMENT",
      ]
      name    = "Management"
      vlan_id = 99
    }
  }
  wan_interface_list = "WAN"
}
