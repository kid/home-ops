include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source                   = "git::git@github.com:kid/terragrunt-infra-catalog//modules/ros-dns?ref=ros-dns/v2.0.0"
  copy_terraform_lock_file = false
}

dependencies {
  paths = [
    "../../rb5009",
  ]
}

inputs = {
  bridge_name = "bridge1"
  dns_static_records = {
    "doorbell.iot-local.home.kidibox.net" = {
      address = "10.0.50.10"
    }
    "k3s-prd-0.k3s.home.kidibox.net" = {
      address = "10.0.40.40"
    }
    "k3s-prd-0.storage.home.kidibox.net" = {
      address = "10.0.20.40"
    }
    "k3s-prd-1.k3s.home.kidibox.net" = {
      address = "10.0.40.41"
    }
    "k3s-prd-1.storage.home.kidibox.net" = {
      address = "10.0.20.41"
    }
    "k3s-prd-2.k3s.home.kidibox.net" = {
      address = "10.0.40.42"
    }
    "k3s-prd-2.storage.home.kidibox.net" = {
      address = "10.0.20.42"
    }
    "node0.srv.home.kidibox.net" = {
      address = "10.0.10.10"
    }
    "node0.storage.home.kidibox.net" = {
      address = "10.0.20.10"
    }
    "node1.srv.home.kidibox.net" = {
      address = "10.0.10.11"
    }
    "sma-inverter.iot-local.home.kidibox.net" = {
      address = "10.0.50.41"
    }
  }
  dns_upstream_servers = [
    "9.9.9.9",
    "149.112.112.112",
  ]
  hostname            = "rb5009"
  mgmt_interface_list = "MANAGEMENT"
  op_item_routeros    = "RB5009 - user - kid"
  op_vault            = "home-ops"
  wan_interface_list  = "WAN"
}
