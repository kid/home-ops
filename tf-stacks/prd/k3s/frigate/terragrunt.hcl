include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/tf-catalog/modules//frigate"
}

inputs = {
  cameras = [
    "doorbell",
    "litters",
  ]
}
