include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/tf-catalog/modules//cloudflared"
}

inputs = {
  account_id   = "fadfc390b1e5fb0ce019b9f7a8917d42"
  cluster_name = "prd"
}
