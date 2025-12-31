include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

include "provider_routeros" {
  path   = "${get_repo_root()}/tf-catalog/modules/_shared/provider-routeros.hcl"
  expose = true
}

terraform {
  source                   = "${get_repo_root()}/tf-catalog/modules/ros//dns"
  copy_terraform_lock_file = false
}

locals {
  interface_lists = include.root.locals.env_config.locals.interface_lists
}

inputs = merge(
  include.root.locals.base_inputs,
  {
    hostname          = "rb5009"
    routeros_endpoint = "10.99.0.1"

    dns_upstream_servers = ["9.9.9.9", "1.1.1.1"]
    dns_static_records = {
      "pve0.kidibox.net"              = { address = "10.0.10.10" }
      "pve1.kidibox.net"              = { address = "10.0.10.11" }
      "ha.kidibox.net"                = { address = "10.0.10.101" }
      "doorbell.iot.home.kidibox.net" = { address = "10.0.101.100" }
      "plex.kidibox.net"              = { address = "10.0.30.100" }
      "prowlarr.kidibox.net"          = { address = "10.0.30.110" }
      "radarr.kidibox.net"            = { address = "10.0.30.120", disabled = true }
      "sonarr.kidibox.net"            = { address = "10.0.30.130", disabled = true }
      "animarr.kidibox.net"           = { address = "10.0.30.140", disabled = true }
      "sabnzbd.kidibox.net"           = { address = "10.0.30.150" }
    }
  },
)
