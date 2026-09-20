include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/tf-catalog/modules//cert-manager"
}

inputs = {
  cluster_name       = "prd"
  account_id         = get_env("CLOUDFLARE_ACCOUNT_ID")
  cloudflare_zone_id = get_env("CLOUDFLARE_ZONE_ID")
}
