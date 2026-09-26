include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/tf-catalog/modules//cert-manager"
}

inputs = {
  account_id         = "fadfc390b1e5fb0ce019b9f7a8917d42"
  cloudflare_zone_id = "dba2b63221015f1957d718defbf6b871"
  cluster_name       = "prd"
}
