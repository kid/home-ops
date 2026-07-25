include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "provider_routeros" {
  path = "${get_repo_root()}/tf-catalog/modules/_shared/provider-routeros.hcl"
}

terraform {
  source                   = "${get_repo_root()}/tf-catalog/modules/ros//capsman"
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
  routeros_endpoint     = "10.99.0.1"
  routeros_secrets_path = "${get_repo_root()}/secrets/prd/routeros.sops.yaml"
  wan_interface_list    = "WAN"
}
