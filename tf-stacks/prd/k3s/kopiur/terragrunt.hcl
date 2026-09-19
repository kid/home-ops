include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/tf-catalog/modules//kopiur-r2"
}

inputs = {
  account_id  = "fadfc390b1e5fb0ce019b9f7a8917d42"
  environment = "prd"
}
