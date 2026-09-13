include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/tf-catalog/modules/kopiur-r2"
}

generate "providers" {
  path      = "providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "onepassword" {}

    provider "cloudflare" {
      api_token = data.onepassword_item.cloudflare_admin.password
    }
  EOF
}
