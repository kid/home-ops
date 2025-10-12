include "root" {
  path = find_in_parent_folders("root.hcl")
  expose = true
}

include "provider_routeros" {
  path = "${get_repo_root()}/tf-catalog/modules/_shared/provider-routeros.hcl"
  expose = true
}

terraform {
  source = "${get_repo_root()}/tf-catalog/modules/ros//base"
}

dependency "lab" {
  config_path = values.lab_path
}

inputs = merge(
  include.root.inputs,
  {
    routeros_endpoint = run_cmd("./get_ros_endpoint.sh", dependency.lab.outputs.oob_ips[values.hostname]),
    certificate_alt_names = ["IP:${dependency.lab.outputs.oob_ips[values.hostname]}"],

    oob_mgmt_ip_address = "${dependency.lab.outputs.oob_ips[values.hostname]}/24"
  },
  values
)
