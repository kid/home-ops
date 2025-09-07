include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "backend" {
  path = find_in_parent_folders("backend.hcl")
}

inputs = {
  ros_hostname = values.ros_hostname

  hostname = values.hostname
}
