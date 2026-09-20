include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/tf-catalog/modules//kopiur-r2"
}

inputs = {
  account_id  = get_env("CLOUDFLARE_ACCOUNT_ID")
  environment = "prd"
}
