include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/tf-catalog/modules//cert-manager"
}

inputs = {
  cluster_name       = "prd"
  account_id         = "fadfc390b1e5fb0ce019b9f7a8917d42"
  cloudflare_zone_id = "" # TODO: set the real zone ID for kidibox.net
  vault_address      = "openbao.kidibox.net"
}
