include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/tf-catalog/modules//argocd"
}

inputs = {
  cluster_name     = "prd"
  github_owner     = "kid"
  github_repo      = "home-ops"
  webhook_hostname = "argo-webhook.kidibox.net"
}
