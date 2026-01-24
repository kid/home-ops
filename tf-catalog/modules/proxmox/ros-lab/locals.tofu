locals {
  tags = ["terraform", "routeros", "lab"]

  vm_id_start = 10991

  devices_vm_ids = { for idx, item in var.devices : item.name => idx + local.vm_id_start }

  devices_interfaces_generated = {
    for _, device in var.devices : device.name =>
    [
      for idx, ifce in device.interfaces : merge(ifce, {
        vlan_id = ifce.type == "wan" ? 10 : (
          ifce.type == "oob" ? 1991 : null
        )
        bridge = ifce.type == "wan" ? "vmbr0" : (
          ifce.type == "trunk" ? "vmbr0" : (
            ifce.type == "port" ? proxmox_virtual_environment_network_linux_bridge.ports[join("-", sort([device.name, ifce.target]))].name : (
          ifce.type == "oob" ? "vmbr0" : null))
        )
      })
    ]
    if device.type == "chr"
  }

  bridges = distinct(flatten([
    for _, device in var.devices : [
      for _, ifce in device.interfaces : join("-", sort([device.name, ifce.target])) if ifce.type == "port"
    ]
  ]))

  images = {
    chr = {
      url                     = "https://download.mikrotik.com/routeros/${var.routeros_version}/chr-${var.routeros_version}.img.zip"
      type                    = "iso"
      file_name               = "chr-${var.routeros_version}.img"
      decompression_algorithm = "gz"
    }
  }
}
