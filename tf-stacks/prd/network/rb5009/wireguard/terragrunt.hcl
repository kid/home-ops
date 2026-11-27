include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/tf-catalog/modules//ros-wireguard"
}

dependencies {
  paths = [
    "../../rb5009",
  ]
}

inputs = {
  address     = "10.0.90.1/24"
  bridge_name = "bridge1"
  dns_upstream_servers = [
    "9.9.9.9",
    "149.112.112.112",
  ]
  hostname            = "rb5009"
  interface_list      = "MANAGEMENT"
  interface_name      = "WireGuard"
  listen_port         = 51820
  mgmt_interface_list = "MANAGEMENT"
  op_item_routeros    = "RB5009 - user - kid"
  op_vault            = "home-ops"
  peers = {
    fw13 = {
      address    = "10.0.90.2"
      public_key = "VU9KFnxmX/hCVfILJOP/9tQ/fn8tsNybd4J+2D4YWSg="
    }
  }
  wan_interface_list = "WAN"
}
