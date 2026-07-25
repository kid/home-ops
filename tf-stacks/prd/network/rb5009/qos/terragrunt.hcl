include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "provider_routeros" {
  path = "${get_repo_root()}/tf-catalog/modules/_shared/provider-routeros.hcl"
}

terraform {
  source                   = "${get_repo_root()}/tf-catalog/modules/ros//qos"
  copy_terraform_lock_file = false
}

inputs = {
  bridge_name = "bridge1"
  dns_upstream_servers = [
    "9.9.9.9",
    "149.112.112.112",
  ]
  hostname              = "rb5009"
  limit_rx              = "900M"
  limit_tx              = "18M"
  mgmt_interface_list   = "MANAGEMENT"
  routeros_endpoint     = "10.99.0.1"
  routeros_secrets_path = "${get_repo_root()}/secrets/prd/routeros.sops.yaml"
  wan_interface         = "ether8"
  wan_interface_list    = "WAN"
}
