include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

include "provider_routeros" {
  path   = "${get_repo_root()}/tf-catalog/modules/_shared/provider-routeros.hcl"
  expose = true
}

terraform {
  source                   = "${get_repo_root()}/tf-catalog//modules/ros/dns"
  copy_terraform_lock_file = false
}

dependencies {
  paths = [".."]
}

inputs = merge(
  include.root.locals.routeros_inputs,
  {
    dns_upstream_servers = ["1.1.1.1", "8.8.8.8"]
  },
)
