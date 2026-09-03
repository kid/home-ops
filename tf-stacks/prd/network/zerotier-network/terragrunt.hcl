include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source                   = "git::git@github.com:kid/terragrunt-infra-catalog//modules/zerotier-network?ref=zerotier-network/v1.0.0"
  copy_terraform_lock_file = false
}

inputs = {
  assignment_pool = {
    end   = "10.147.20.254"
    start = "10.147.20.2"
  }
  network_name             = "home-lan"
  op_item_zerotier_central = "ZeroTier Central - API Token"
  op_vault                 = "home-ops"
  router_ip                = "10.147.20.1"
  router_member_id         = "TODO-rb5009-zerotier-identity"
  routes = [
    {
      target = "10.0.100.0/24"
    },
    {
      target = "10.0.10.0/24"
    },
    {
      target = "10.99.0.0/16"
    },
  ]
}
