include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/tf-catalog/modules//kopiur-r2"
}

inputs = {
  account_id = "" # TODO: set your Cloudflare account ID
}
