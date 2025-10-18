locals {
  units_path = find_in_parent_folders("tf-catalog/units")
}

unit "ros-lab" {
  source = "${local.units_path}/proxmox/ros-lab"
  path = "ros-lab"

  values = {
    routeros_version = "7.20.1"
    devices = [
      { 
        name = "router"
        type = "chr"
        interfaces = [
          { type = "oob" },
          { type = "wan" },
          { type = "port", target = "switch" },
          { type = "port", target = "vm1" },
        ]
      },
      { 
        name = "switch"
        type = "chr"
        interfaces = [
          { type = "oob" },
          { type = "port", target = "router" },
        ]
      },
      {
        name = "vm1"
        type = "debian"
        interfaces = [
          { type = "port", target = "router" },
        ]
      }
    ]

    ssh_username = "kid"
    ssh_password = "foobar"
    ssh_keys = [file("~/.ssh/id_ed25519.pub")]
  }
}
