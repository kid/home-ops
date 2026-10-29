include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/tf-catalog/modules//kanidm"
}

inputs = {
  op_vault      = "home-ops-prd"
  smtp_password = get_env("GOOGLE_APP_PASSWORD")
}
