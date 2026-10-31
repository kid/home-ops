include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/tf-catalog/modules//flux-webhook"
}

inputs = {
  github_owner       = "kid"
  github_repo        = "home-ops"
  receiver_name      = "github"
  receiver_namespace = "flux-system"
  token_item         = "flux-github-webhook"
  webhook_hostname   = "flux-webhook.kidibox.net"
}
