locals {
  bootstrap = tobool(get_env("BOOTSTRAP", "false"))
  scheme = local.bootstrap ? "http" : "https"
}

include "root" {
  path = find_in_parent_folders("root.hcl")
  expose = true
}

include "provider_ros" {
  path = "${get_repo_root()}/tf-catalog/modules/ros/_shared/provider.hcl"
  expose = true
}

terraform {
  source = "${get_repo_root()}/tf-catalog/modules/ros//base"
}

inputs = merge(
  include.root.inputs,
  include.provider_ros.inputs,
  {
    ros_hostname = "${local.scheme}://${values.ip_address}",

    certificate_common_name = values.ip_address,
  },
  values
)
