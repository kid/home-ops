locals {
  units_path = find_in_parent_folders("tf-catalog/units")
  bootstrap = tobool(get_env("BOOTSTRAP", "false"))
  scheme = local.bootstrap ? "http" : "https"
}

unit "base" {
  source = "${local.units_path}/ros/base"
  path = "base"

  values = {
    ip_address = "10.0.10.192"
    hostname = "switch",
    # certificate_common_name = "10.0.10.192"
    # certificate_unit = "lab"
  }
}
