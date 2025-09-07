locals {
  units_path = find_in_parent_folders("tf-catalog/modules")
}

unit "base" {
  source = "${local.units_path}/ros/base"
  path = "base"

  values = {
    ros_hostname = "http://10.0.10.192"
      hostname = "switch",

  }
}
