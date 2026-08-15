locals {
  openbao_init = yamldecode(sops_decrypt_file("${get_repo_root()}/secrets/prd/openbao-init.sops.yaml"))
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source                   = "${get_repo_root()}/tf-modules/openbao-config"
  copy_terraform_lock_file = false
}

inputs = {
  address           = "http://openbao.kidibox.net:8200"
  approle_role_id   = "external-secrets"
  approle_role_name = "external-secrets"
  kv_mount          = "secret"
  root_token        = local.openbao_init.root_token
  secret_name       = "openbao-approle"
  secret_namespace  = "external-secrets"
}
