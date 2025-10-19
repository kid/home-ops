locals {
  certificate_unit = "lab"
  environment = "dev"

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

  vlans = {
    Management = {
      name = "Management"
      vlan_id = 199
      cidr_network = "10.199.0.0"
      cidr_prefix = 16
      domain = "mgmt.lab.kidibox.net"
      gateway = "10.199.0.1"
      dns_servers = ["10.199.0.0"]
      dhcp_pool = ["10.199.255.200-10.199.255.255"]
    }
  }
}
