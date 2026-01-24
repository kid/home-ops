locals {
  proxmox_oui_prefix = [188, 36, 17]
  lab_oui_prefix     = 128

  oob_cidr        = "192.168.89.0/24"
  oob_cidr_prefix = tonumber(split("/", local.oob_cidr)[1])

  devices_config = [
    {
      name = "router"
      type = "chr"
      interfaces = [
        { type = "oob" },
        { type = "wan" },
        { type = "port", target = "switch" },
        { type = "port", target = "trusted1" },
        { type = "port", target = "guest1" },
        { type = "trunk" },
      ]
    },
    {
      name = "switch"
      type = "chr"
      interfaces = [
        { type = "oob" },
        { type = "port", target = "router" },
        { type = "port", target = "trusted2" },
        { type = "port", target = "guest2" },
      ]
    },
    {
      name = "trusted1"
      type = "chr"
      interfaces = [
        { type = "oob" },
        { type = "port", target = "router" },
      ]
    },
    {
      name = "guest1"
      type = "chr"
      interfaces = [
        { type = "oob" },
        { type = "port", target = "router" },
      ]
    },
    {
      name = "trusted2"
      type = "chr"
      interfaces = [
        { type = "oob" },
        { type = "port", target = "switch" },
      ]
    },
    {
      name = "guest2"
      type = "chr"
      interfaces = [
        { type = "oob" },
        { type = "port", target = "switch" },
      ]
    }
  ]

  devices = [
    for dev_idx, dev in local.devices_config :
    merge(dev, {
      interfaces = [
        for ifce_idx, ifce in dev.interfaces :
        merge(
          ifce,
          ifce.type == "oob" ? { ip_address = cidrhost(local.oob_cidr, dev_idx + 2) } : {},
          {
            name        = format("ether%d", ifce_idx + 1)
            mac_address = join(":", formatlist("%02X", concat(local.proxmox_oui_prefix, [local.lab_oui_prefix, dev_idx + 1, ifce_idx + 1])))
          },
        )
      ]
    })
  ]

  devices_map = { for _, dev in local.devices : dev.name => dev }
}
