include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source                   = "git::git@github.com:kid/terragrunt-infra-catalog//modules/ros-qos?ref=feat/onepassword-secrets"
  copy_terraform_lock_file = false
}

inputs = {
  bridge_name = "bridge1"
  dns_upstream_servers = [
    "9.9.9.9",
    "149.112.112.112",
  ]
  hostname            = "rb5009"
  limit_rx            = "900M"
  limit_tx            = "18M"
  mgmt_interface_list = "MANAGEMENT"
  op_item_routeros    = "RB5009 - admin"
  op_vault            = "home-ops"
  wan_interface       = "ether8"
  wan_interface_list  = "WAN"
}
