include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source                   = "${get_repo_root()}/tf-modules/onepassword-items"
  copy_terraform_lock_file = false
}

inputs = {
  items = [
    {
      category = "password"
      fields = [
        {
          generate = false
          length   = 32
          name     = "token"
        },
      ]
      title = "cloudflare-dns-api-token"
      vault = "home-ops"
    },
  ]
}
