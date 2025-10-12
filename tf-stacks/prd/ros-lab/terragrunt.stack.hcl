locals {
  units_path = find_in_parent_folders("tf-catalog/units")
}

unit "ros-lab" {
  source = "${local.units_path}/proxmox/ros-lab"
  path = "ros-lab"

  values = {
    routeros_version = "7.20"
    devices = [
      { 
        name = "router"
        interfaces = [
          { type = "wan" },
          { type = "port", target = "switch" }
        ]
      },
      { 
        name = "switch"
        interfaces = [
          { type = "port", target = "router" }
        ]
      },
    ]
  }
}
