include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/tf-catalog/modules//renovate-webhook"
}

inputs = {
  github_owner = "kid"
  push_schedules = {
    neovim = [
      "home-ops",
    ]
  }
  repositories = [
    "home-ops",
    "nixfiles-work",
    "neovim",
  ]
  schedule_url = "https://renovate-webhook.kidibox.net/webhook/v1/schedule?namespace=renovate&job=renovate"
  token_item   = "renovate-webhook"
  webhook_url  = "https://renovate-webhook.kidibox.net/webhook/v1/github?namespace=renovate&job=renovate"
}
