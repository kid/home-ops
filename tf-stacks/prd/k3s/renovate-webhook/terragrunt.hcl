include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/tf-catalog/modules//renovate-webhook"
}

inputs = {
  dispatch_repositories = [
    "nixfiles",
    "neovim",
  ]
  github_owner = "kid"
  repositories = [
    "home-ops",
    "nixfiles",
    "nixfiles-work",
    "neovim",
  ]
  token_item  = "renovate-webhook"
  webhook_url = "https://renovate-webhook.kidibox.net/webhook/v1/github?namespace=renovate&job=renovate"
}
