locals {
  environment = "prd"
  tld         = "kidibox.net"

  env_cidr         = cidrsubnet("10.0.0.0/8", 1, 0)
  env_cidr_network = split("/", local.env_cidr)
  env_cidr_prefix  = tonumber(split("/", local.env_cidr)[1])

  interface_lists = {
    MANAGEMENT = "MANAGEMENT"
    WAN        = "WAN"
  }

  vlans = {}
}
