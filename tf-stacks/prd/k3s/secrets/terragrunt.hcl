include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/tf-catalog/modules//cluster-secrets"
}

dependency "kopiur_r2" {
  config_path = "../kopiur"

  mock_outputs = {
    access_key_id     = "mock"
    secret_access_key = "mock"
  }
  mock_outputs_allowed_terraform_commands = ["init", "plan"]
}

inputs = {
  cluster_name             = "prd"
  account_id               = "fadfc390b1e5fb0ce019b9f7a8917d42"
  kopiur_access_key_id     = dependency.kopiur_r2.outputs.access_key_id
  kopiur_secret_access_key = dependency.kopiur_r2.outputs.secret_access_key
  cloudflare_zone_id       = "" # TODO: set the real zone ID for kidibox.net

  # Leave enable_vault/vault_address/vault_role_id/vault_secret_id unset
  # until OpenBao (Stage 4) is up and its approle role/secret ID have been
  # fetched (see modules/den/aspects/kubernetes/openbao/default.nix).
}
