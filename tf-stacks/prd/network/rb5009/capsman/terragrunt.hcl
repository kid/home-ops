include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source                   = "git::git@github.com:kid/terragrunt-infra-catalog//modules/ros-capsman?ref=feat/onepassword-secrets"
  copy_terraform_lock_file = false
}

dependencies {
  paths = [
    "../../rb5009",
  ]
}

inputs = {
  bridge_name = "bridge1"
  capsman_interfaces = [
    "Management",
  ]
  dns_upstream_servers = [
    "9.9.9.9",
    "149.112.112.112",
  ]
  hostname            = "rb5009"
  mgmt_interface_list = "MANAGEMENT"
  op_item_routeros    = "RB5009 - admin"
  op_item_wifi        = "RB5009 - wifi"
  op_vault            = "home-ops"
  passphrase_groups = {
    Guest = {
      isolated = true
      vlan_id  = 101
    }
    IotInternet = {
      isolated = true
      vlan_id  = 51
    }
    IotLocal = {
      isolated = true
      vlan_id  = 50
    }
    Trusted = {
      vlan_id = 100
    }
  }
  wan_interface_list = "WAN"
}
