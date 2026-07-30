include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source                   = "git::git@github.com:kid/terragrunt-infra-catalog//modules/ros-dns?ref=feat/onepassword-secrets"
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
    "animarr.kidibox.net" = {
      address = "10.0.30.140"
    }
    "doorbell.iot.home.kidibox.net" = {
      address = "10.0.101.100"
    }
    "ha.kidibox.net" = {
      address = "10.0.10.101"
    }
    "plex.kidibox.net" = {
      address = "10.0.30.100"
    }
    "prowlarr.kidibox.net" = {
      address = "10.0.30.110"
    }
    "pve0.kidibox.net" = {
      address = "10.0.10.10"
    }
    "pve1.kidibox.net" = {
      address = "10.0.10.11"
    }
    "radarr.kidibox.net" = {
      address = "10.0.30.120"
    }
    "sabnzbd.kidibox.net" = {
      address = "10.0.30.150"
    }
    "sonarr.kidibox.net" = {
      address = "10.0.30.130"
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
