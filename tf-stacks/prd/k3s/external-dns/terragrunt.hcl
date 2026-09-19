include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/tf-catalog/modules//external-dns"
}

inputs = {
  cluster_name  = "prd"
  vault_address = "" # TODO: OpenBao's LoadBalancer IP, once it's deployed
}
