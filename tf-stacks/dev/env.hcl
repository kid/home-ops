locals {
  certificate_unit = "lab"
  environment = "dev"

  vlans = {
    Management = {
      name = "Management"
      vlan_id = 199
      cidr_network = "10.199.0.0"
      cidr_prefix = 16
    }
  }
}
