include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source                   = "git::git@github.com:kid/terragrunt-infra-catalog//modules/ros-firewall?ref=6cfae877ca29ef8453912356d008e287489404f9"
  copy_terraform_lock_file = false
}

dependencies {
  paths = [
    "../../rb5009",
  ]
}

inputs = {
  bridge_name = "bridge1"
  dns_upstream_servers = [
    "9.9.9.9",
    "149.112.112.112",
  ]
  hostname            = "rb5009"
  mgmt_interface_list = "MANAGEMENT"
  op_item_routeros    = "RB5009 - user - kid"
  op_vault            = "home-ops"
  vlans = {
    Guest = {
      address = "10.0.101.1"
      name    = "Guest"
      vlan_id = 101
    }
    IotInternet = {
      address = "10.0.51.1"
      name    = "IotInternet"
      vlan_id = 51
    }
    IotLocal = {
      address = "10.0.50.1"
      name    = "IotLocal"
      vlan_id = 50
    }
    K3s = {
      address = "10.0.40.1"
      name    = "K3s"
      vlan_id = 40
    }
    Management = {
      address = "10.99.0.1"
      name    = "Management"
      vlan_id = 99
    }
    Media = {
      address = "10.0.30.1"
      name    = "Media"
      vlan_id = 30
    }
    Servers = {
      address = "10.0.10.1"
      name    = "Servers"
      vlan_id = 10
    }
    Storage = {
      address = "10.0.20.1"
      name    = "Storage"
      vlan_id = 20
    }
    Trusted = {
      address = "10.0.100.1"
      name    = "Trusted"
      vlan_id = 100
    }
  }
  vlans_forward_rules = {
    Guest = [
      {
        action             = "accept"
        comment            = "Allow WAN"
        out_interface_list = "WAN"
      },
    ]
    IotInternet = [
      {
        action             = "accept"
        comment            = "Allow WAN"
        out_interface_list = "WAN"
      },
    ]
    IotLocal = [
      {
        action             = "accept"
        comment            = "Allow WAN"
        disabled           = true
        out_interface_list = "WAN"
      },
    ]
    K3s = [
      {
        action             = "accept"
        comment            = "Allow WAN"
        out_interface_list = "WAN"
      },
      {
        action      = "accept"
        comment     = "Allow Traffic to load balancer ips"
        dst_address = "10.0.42.0/24"
      },
      {
        action      = "accept"
        comment     = "Allow access to crs320 for mikrotik-exporter"
        dst_address = "10.99.0.2"
        dst_port    = 8729
        protocol    = "tcp"
      },
    ]
    Management = [
      {
        action             = "accept"
        comment            = "Allow WAN"
        out_interface_list = "WAN"
      },
    ]
    Media = [
      {
        action             = "accept"
        comment            = "Allow WAN"
        out_interface_list = "WAN"
      },
      {
        action      = "accept"
        comment     = "Allow cloudflared access to HomeAssistant"
        dst_address = "10.0.10.101"
        src_address = "10.0.30.11"
      },
    ]
    Servers = [
      {
        action             = "accept"
        comment            = "Allow WAN"
        out_interface_list = "WAN"
      },
      {
        action             = "accept"
        comment            = "Allow access to all vlans"
        out_interface_list = "all"
      },
    ]
    Trusted = [
      {
        action             = "accept"
        comment            = "Allow WAN"
        out_interface_list = "WAN"
      },
      {
        action        = "accept"
        comment       = "Allow access to Management"
        out_interface = "Management"
      },
      {
        action             = "accept"
        comment            = "Allow access to all vlans"
        out_interface_list = "all"
      },
    ]
  }
  vlans_input_rules = {
    K3s = [
      {
        action      = "accept"
        comment     = "Allow access to Management from K3s for external-dns"
        dst_address = "10.99.0.1"
        dst_port    = 443
        protocol    = "tcp"
      },
      {
        action      = "accept"
        comment     = "Allow access to Management from K3s for mikrotik-exporter"
        dst_address = "10.99.0.1"
        dst_port    = 8729
        protocol    = "tcp"
      },
    ]
    Trusted = [
      {
        action      = "accept"
        comment     = "Allow access to Management from Trusted"
        dst_address = "10.99.0.1"
      },
    ]
  }
  wan_interface_list = "WAN"
}
