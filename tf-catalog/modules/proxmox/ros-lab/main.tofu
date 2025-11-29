resource "proxmox_virtual_environment_download_file" "images" {
  for_each                = local.images
  datastore_id            = "local"
  node_name               = "pve1"
  url                     = each.value.url
  content_type            = try(each.value.type, null)
  file_name               = try(each.value.file_name, null)
  decompression_algorithm = try(each.value.decompression_algorithm, null)
  overwrite               = false
}

resource "proxmox_virtual_environment_network_linux_bridge" "ports" {
  for_each   = { for idx, bridge in local.bridges : bridge => { name = bridge, idx = idx } }
  node_name  = "pve1"
  name       = format("lab%02d", each.value.idx)
  vlan_aware = false
}

resource "routeros_ip_dhcp_server_lease" "leases" {
  for_each = merge([
    for _, dev in var.devices : {
      for _, ifce in dev.interfaces :
      format("%s_%s", dev.name, ifce.name) => ifce
      if ifce.ip_address != null
    }
  ]...)

  mac_address = each.value.mac_address
  address     = each.value.ip_address
}

resource "proxmox_virtual_environment_vm" "devices" {
  depends_on = [
    proxmox_virtual_environment_network_linux_bridge.ports,
    routeros_ip_dhcp_server_lease.leases,
  ]

  for_each = { for idx, item in var.devices : item.name => item if item.type == "chr" }

  vm_id = local.devices_vm_ids[each.key]
  name  = "lab-${each.key}"
  tags  = local.tags

  node_name = "pve1"

  agent {
    enabled = true
  }

  stop_on_destroy = true
  scsi_hardware   = "virtio-scsi-single"

  disk {
    datastore_id = "local-zfs"
    file_id      = proxmox_virtual_environment_download_file.images[each.value.type].id
    file_format  = "raw"
    interface    = "virtio0"
    size         = 10
    iothread     = true
    discard      = "on"
  }

  dynamic "network_device" {
    for_each = try(local.devices_interfaces_generated[each.key], {})
    iterator = ifce

    content {
      bridge      = ifce.value["bridge"]
      vlan_id     = ifce.value["vlan_id"]
      mac_address = ifce.value["mac_address"]
    }
  }

  lifecycle {
    ignore_changes = [disk[0].file_id]
  }

  provisioner "local-exec" {
    interpreter = ["expect", "-c"]
    command = templatefile("./ros-setup.exp", {
      ip = [for _, ifce in each.value.interfaces : ifce.ip_address if ifce.type == "oob"][0]
    })
  }
}
