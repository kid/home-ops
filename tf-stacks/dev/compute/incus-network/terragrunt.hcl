include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/tf-catalog/modules/incus-network"
}

inputs = {
  name         = "incusbr0"
  ipv4_address = "10.150.19.1/24"
}
