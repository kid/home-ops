locals {
  openbao_init = yamldecode(sops_decrypt_file("${get_repo_root()}/secrets/prd/openbao-init.sops.yaml"))
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source                   = "${get_repo_root()}/tf-modules/openbao-items"
  copy_terraform_lock_file = false
}

inputs = {
  address = "http://openbao.kidibox.net:8200"
  items = [
    {
      fields = [
        {
          generate = false
          length   = 32
          name     = "token"
        },
      ]
      path = "cert-manager/cloudflare-dns-api-token"
    },
  ]
  kv_mount   = "secret"
  root_token = local.openbao_init.root_token
}
