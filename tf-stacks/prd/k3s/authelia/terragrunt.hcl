include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/tf-catalog/modules//authelia"
}

inputs = {
  op_vault = "home-ops-prd"
  url      = "https://auth.kidibox.net"

  mail_domain        = "mail.kidibox.net"
  mailgun_region     = "eu"
  cloudflare_zone_id = "dba2b63221015f1957d718defbf6b871"

  users = {
    kid = {
      displayname = "Arnaud Rebts"
      email       = "arnaud.rebts@gmail.com"
      groups      = ["admins"]
    }
  }
}
