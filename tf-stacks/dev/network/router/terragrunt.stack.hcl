locals {
  units_path = find_in_parent_folders("tf-catalog/units")
  ip_address = "10.0.10.191"
}

unit "base" {
  source = "${local.units_path}/ros/base"
  path = "base"

  values = {
    ip_address = local.ip_address
    hostname = "router",
  }
}
