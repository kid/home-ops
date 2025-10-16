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
  for_each  = { for idx, bridge in local.bridges : bridge => { name = bridge, idx = idx } }
  node_name = "pve1"
  name      = format("vmbr1991%02d", each.value.idx)
}

resource "proxmox_virtual_environment_vm" "devices" {
  depends_on = [proxmox_virtual_environment_network_linux_bridge.ports]
  for_each   = { for idx, item in var.devices : item.name => item if item.type == "chr" }

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
      bridge  = ifce.value["bridge"]
      vlan_id = ifce.value["vlan_id"]
    }
  }
}

resource "terraform_data" "initial_provisioning" {
  for_each = { for idx, item in var.devices : item.name => item if item.type == "chr" }

  provisioner "local-exec" {
    interpreter = ["expect", "-c"]
    command = templatefile("./ros-setup.exp", {
      ip     = proxmox_virtual_environment_vm.devices[each.key].ipv4_addresses[0][0]
      oob_ip = "${local.devices_oob_ips[each.key]}/${var.oob_prefix}"
    })
  }
}

output "oob_ips" {
  value = local.devices_oob_ips
}
