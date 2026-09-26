include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/tf-catalog/modules//authelia"
}

inputs = {
  op_vault      = "home-ops-prd"
  smtp_password = get_env("GOOGLE_APP_PASSWORD")
  url           = "https://auth.kidibox.net"
  users = {
    kid = {
      displayname = "Arnaud Rebts"
      email       = "arnaud.rebts@gmail.com"
      groups = [
        "admins",
      ]
    }
  }
}
