locals {
  hostname = "router"
}

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

include "provider_routeros" {
  path   = "${get_repo_root()}/tf-catalog/modules/_shared/provider-routeros.hcl"
  expose = true
}

terraform {
  source = "${get_repo_root()}/tf-catalog//modules/ros/router"
}

dependencies {
  paths = ["../"]
}

dependency "lab" {
  config_path = "../../../lab"

  mock_outputs = {
    oob_ips = {
      router = ""
      switch = ""
    }
  }
}

inputs = merge(
  include.root.inputs,
  {
    routeros_endpoint = "https://${dependency.lab.outputs.oob_ips[local.hostname]}",
    wan_interface     = "ether2"
  },
)
