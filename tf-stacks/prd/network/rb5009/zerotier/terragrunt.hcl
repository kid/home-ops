include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source                   = "git::git@github.com:kid/terragrunt-infra-catalog//modules/ros-zerotier?ref=ros-zerotier/v1.0.0"
  copy_terraform_lock_file = false
}

dependencies {
  paths = [
    "../../rb5009",
  ]
}

inputs = {
  allow_default = false
  allow_global  = false
  allow_managed = true
  bridge_name   = "bridge1"
  dns_upstream_servers = [
    "9.9.9.9",
    "149.112.112.112",
  ]
  hostname            = "rb5009"
  instance_name       = "zerotier1"
  interface_list      = "ZEROTIER"
  interface_name      = "zerotier1"
  mgmt_interface_list = "MANAGEMENT"
  network_id          = "TODO-zerotier-network-id"
  op_item_routeros    = "RB5009 - user - kid"
  op_vault            = "home-ops"
  wan_interface_list  = "WAN"
}
