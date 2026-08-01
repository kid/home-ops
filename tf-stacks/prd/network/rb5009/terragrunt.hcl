include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source                   = "git::git@github.com:kid/terragrunt-infra-catalog//modules/ros-base?ref=feat/onepassword-secrets"
  copy_terraform_lock_file = false
}

inputs = {
  bridge_name = "bridge1"
  certificate_alt_names = [
    "DNS:rb5009",
    "DNS:rb5009.kidibox.net",
    "IP:10.99.0.1",
    "IP:192.168.88.1",
  ]
  dhcp_clients = [
    {
      interface = "ether8"
    },
  ]
  dhcp_servers = {
    Guest = {
      cidr = "10.0.101.0/24"
      dns_servers = [
        "9.9.9.9",
        "149.112.112.112",
      ]
      domain  = "iot.home.kidibox.net"
      gateway = "10.0.101.1"
      ntp_servers = [
        "162.159.200.1",
        "162.159.200.123",
      ]
    }
    IotInternet = {
      cidr = "10.0.51.0/24"
      dns_servers = [
        "9.9.9.9",
        "149.112.112.112",
      ]
      domain  = "iot-internet.home.kidibox.net"
      gateway = "10.0.51.1"
      ntp_servers = [
        "162.159.200.1",
        "162.159.200.123",
      ]
    }
    IotLocal = {
      cidr = "10.0.50.0/24"
      dns_servers = [
        "10.0.50.1",
      ]
      domain  = "iot-local.home.kidibox.net"
      gateway = "10.0.50.1"
      ntp_servers = [
        "10.0.50.1",
      ]
    }
    K3s = {
      cidr = "10.0.40.0/24"
      dns_servers = [
        "10.0.40.1",
      ]
      domain  = "k3s.home.kidibox.net"
      gateway = "10.0.40.1"
      ntp_servers = [
        "10.0.40.1",
      ]
    }
    Management = {
      cidr = "10.99.0.0/16"
      dns_servers = [
        "10.99.0.1",
      ]
      domain  = "mgmt.home.kidibox.net"
      gateway = "10.99.0.1"
      ntp_servers = [
        "10.99.0.1",
      ]
    }
    Media = {
      cidr = "10.0.30.0/24"
      dns_servers = [
        "10.0.30.1",
      ]
      domain  = "media.home.kidibox.net"
      gateway = "10.0.30.1"
      ntp_servers = [
        "10.0.30.1",
      ]
    }
    Servers = {
      cidr = "10.0.10.0/24"
      dns_servers = [
        "10.0.10.1",
      ]
      domain  = "srv.home.kidibox.net"
      gateway = "10.0.10.1"
      ntp_servers = [
        "10.0.10.1",
      ]
    }
    Storage = {
      cidr = "10.0.20.0/24"
      dns_servers = [
        "10.0.20.1",
      ]
      domain  = "storage.home.kidibox.net"
      gateway = "10.0.20.1"
      ntp_servers = [
        "10.0.20.1",
      ]
    }
    Trusted = {
      cidr = "10.0.100.0/24"
      dns_servers = [
        "10.0.100.1",
      ]
      domain  = "lan.home.kidibox.net"
      gateway = "10.0.100.1"
      ntp_servers = [
        "10.0.100.1",
      ]
    }
    ether7 = {
      cidr        = "192.168.88.0/24"
      dns_servers = []
      gateway     = null
    }
  }
  dhcp_static_leases = {
    IotInternet = [
      {
        address = "10.0.51.30"
        mac     = "b0:4a:39:98:1c:cb"
        name    = "roborock-vacuum-a38"
      },
      {
        address = "10.0.51.31"
        mac     = "70:c9:32:4e:21:7d"
        name    = "dreame_vacuum_r2465a"
      },
    ]
    IotLocal = [
      {
        address = "10.0.50.10"
        mac     = "ec:71:db:26:a9:37"
        name    = "doorbell"
      },
      {
        address = "10.0.50.11"
        mac     = "e0:01:c7:e4:e0:f3"
        name    = "litters camera"
      },
      {
        address = "10.0.50.20"
        mac     = "f0:86:20:10:84:18"
        name    = "LGwebOSTV"
      },
      {
        address = "10.0.50.21"
        mac     = "00:06:78:40:24:0a"
        name    = "denon"
      },
      {
        address = "10.0.50.30"
        mac     = "88:12:ac:04:36:44"
        name    = "Somfy Box"
      },
    ]
    Management = [
      {
        address = "10.99.0.2"
        mac     = "f4:1e:57:d1:75:94"
        name    = "crs320"
      },
      {
        address = "10.99.0.10"
        mac     = "48:a9:8a:cc:6d:62"
        name    = "capxr0"
      },
      {
        address = "10.99.0.11"
        mac     = "48:a9:8a:ba:2a:6e"
        name    = "capxr1"
      },
      {
        address = "10.99.10.10"
        mac     = "d0:50:99:f7:ee:15"
        name    = "pve0-ipmi"
      },
      {
        address = "10.99.10.11"
        mac     = "dc:a6:32:06:69:9a"
        name    = "pikvm"
      },
    ]
    Media = [
      {
        address = "10.0.30.11"
        mac     = "bc:24:11:bf:d2:cb"
        name    = "cloudflared1"
      },
      {
        address = "10.0.30.126"
        mac     = "bc:24:11:9f:50:bf"
        name    = "truenas"
      },
    ]
    Servers = [
      {
        address = "10.0.10.10"
        mac     = "a6:34:58:9f:98:09"
        name    = "pve0"
      },
      {
        address = "10.0.10.11"
        mac     = "be:4f:11:f4:ba:61"
        name    = "pve1"
      },
      {
        address = "10.0.10.101"
        mac     = "52:54:00:93:9b:8f"
        name    = "homeassistant"
      },
    ]
    Trusted = [
      {
        address = "10.0.100.108"
        mac     = "08:d1:f9:20:b1:c4"
        name    = "everything-presence-lite-20b1c4"
      },
      {
        address = "10.0.100.137"
        mac     = "bc:24:11:42:5b:fc"
        name    = "prtsrv"
      },
      {
        address = "10.0.100.212"
        mac     = "48:b0:2d:18:ec:cd"
        name    = "shield"
      },
    ]
  }
  dns_upstream_servers = [
    "9.9.9.9",
    "149.112.112.112",
  ]
  ethernet_interfaces = {
    ether1 = {
      comment = "pve1"
      tagged = [
        10,
        20,
        30,
        40,
        50,
        51,
        99,
        100,
        101,
      ]
    }
    ether2 = {
      comment  = "switch"
      untagged = 99
    }
    ether3 = {
      comment = "capxr1"
      tagged = [
        10,
        20,
        30,
        40,
        50,
        51,
        99,
        100,
        101,
      ]
    }
    ether4 = {
      comment = "capxr0"
      tagged = [
        10,
        20,
        30,
        40,
        50,
        51,
        99,
        100,
        101,
      ]
    }
    ether7 = {
      bridge_port = false
      comment     = "oob"
      interface_lists = [
        "MANAGEMENT",
      ]
    }
    ether8 = {
      bridge_port = false
      comment     = "wan"
      interface_lists = [
        "WAN",
      ]
    }
    sfp-sfpplus1 = {
      comment = "uplink to crs320"
      tagged = [
        10,
        20,
        30,
        40,
        50,
        51,
        99,
        100,
        101,
      ]
    }
  }
  hostname = "rb5009"
  ip_addresses = {
    Guest       = "10.0.101.1/24"
    IotInternet = "10.0.51.1/24"
    IotLocal    = "10.0.50.1/24"
    K3s         = "10.0.40.1/24"
    Management  = "10.99.0.1/16"
    Media       = "10.0.30.1/24"
    Servers     = "10.0.10.1/24"
    Storage     = "10.0.20.1/24"
    Trusted     = "10.0.100.1/24"
    ether7      = "192.168.88.1/24"
    ether8      = "192.168.100.2/24"
  }
  mgmt_interface_list = "MANAGEMENT"
  ntp_server_enabled  = true
  op_item_routeros    = "RB5009 - user - kid"
  op_vault            = "home-ops"
  routeros_endpoint   = "10.99.0.1"
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
      disabled = true
    }
    external-dns = {
      group         = "external-dns"
      password_item = "RB5009 - user - external-dns"
    }
    kid = {
      group         = "full"
      password_item = "RB5009 - user - kid"
      ssh_keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAcnmLrPeTJeKsasfU0qn4sP4lBNeOUgRG4iZDS8nyEo kid@vulkan",
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHIM3nsk3HxvEcplSqwynh9V2NzlYdI10mrR746SiJZb kid@fw13",
      ]
    }
    metrics = {
      group         = "metrics"
      password_item = "RB5009 - user - metrics"
    }
  }
  vlans = {
    Guest = {
      name    = "Guest"
      vlan_id = 101
    }
    IotInternet = {
      name    = "IotInternet"
      vlan_id = 51
    }
    IotLocal = {
      name    = "IotLocal"
      vlan_id = 50
    }
    K3s = {
      name    = "K3s"
      vlan_id = 40
    }
    Management = {
      interface_lists = [
        "MANAGEMENT",
      ]
      name    = "Management"
      vlan_id = 99
    }
    Media = {
      name    = "Media"
      vlan_id = 30
    }
    Servers = {
      name    = "Servers"
      vlan_id = 10
    }
    Storage = {
      mtu     = 9000
      name    = "Storage"
      vlan_id = 20
    }
    Trusted = {
      name    = "Trusted"
      vlan_id = 100
    }
  }
  wan_interface_list = "WAN"
}
