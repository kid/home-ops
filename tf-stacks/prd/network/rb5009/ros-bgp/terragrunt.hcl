include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source                   = "git::git@github.com:kid/terragrunt-infra-catalog//modules/ros-bgp?ref=ros-bgp/v1.0.0"
  copy_terraform_lock_file = false
}

dependencies {
  paths = [
    "../../rb5009",
  ]
}

inputs = {
  bgp_hold_time      = "90s"
  bgp_keepalive_time = "30s"
  bgp_local_asn      = 64512
  bgp_remote_asn     = 64513
  bgp_router_id      = "10.0.40.1"
  bridge_name        = "bridge1"
  cluster_name       = "prd"
  dns_upstream_servers = [
    "9.9.9.9",
    "149.112.112.112",
  ]
  hostname            = "rb5009"
  mgmt_interface_list = "MANAGEMENT"
  nodes = {
    node1 = {
      ip_address = "10.0.40.10"
    }
  }
  op_item_routeros   = "RB5009 - user - kid"
  op_vault           = "home-ops"
  wan_interface_list = "WAN"
}
