include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/tf-catalog/modules//mailgun"
}

inputs = {
  op_vault           = "home-ops-prd"
  domain             = "mail.kidibox.net"
  region             = "us"
  cloudflare_zone_id = "dba2b63221015f1957d718defbf6b871"
}
