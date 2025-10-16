include "root" {
  path = find_in_parent_folders("root.hcl")
  expose = true
}

include "provider_routeros" {
  path = "${get_repo_root()}/tf-catalog/modules/_shared/provider-routeros.hcl"
  expose = true
}

terraform {
  source = "${get_repo_root()}/tf-catalog//units/ros/router"
}

dependency "lab" {
  config_path = values.lab_path

  mock_outputs = {
    oob_ips = { 
      router = "" 
      switch = ""
    }
  }
}

dependencies {
  paths = ["../base"]
}

inputs = merge(
  include.root.inputs,
  {
    routeros_endpoint = "https://${dependency.lab.outputs.oob_ips[values.hostname]}",
  },
  values
)
