locals {
  tags = ["terraform", "routeros", "lab"]

  vm_id_start = 10991

  oob_cidr = "${var.oob_network}/${var.oob_prefix}"

  devices_vm_ids  = { for idx, item in var.devices : item.name => idx + local.vm_id_start }
  devices_oob_ips = { for idx, item in var.devices : item.name => cidrhost(local.oob_cidr, idx + 2) }

  devices_interfaces_generated = {
    for _, device in var.devices : device.name =>
    [
      for _, ifce in device.interfaces : {
        vlan_id = ifce.type == "wan" ? 10 : null
        bridge  = ifce.type == "wan" ? "vmbr0" : ifce.type == "port" ? proxmox_virtual_environment_network_linux_bridge.ports[join("-", sort([device.name, ifce.target]))].name : null
      }
    ]
  }

  bridges = distinct(flatten([
    for _, device in var.devices : [
      for _, ifce in device.interfaces : join("-", sort([device.name, ifce.target])) if ifce.type == "port"
    ]
  ]))
}

resource "proxmox_virtual_environment_download_file" "chr" {
  content_type            = "iso"
  datastore_id            = "local"
  node_name               = "pve1"
  url                     = "https://download.mikrotik.com/routeros/${var.routeros_version}/chr-${var.routeros_version}.img.zip"
  file_name               = "chr-${var.routeros_version}.img"
  decompression_algorithm = "gz"
  overwrite               = false
}

resource "proxmox_virtual_environment_network_linux_bridge" "ports" {
  for_each  = { for idx, bridge in local.bridges : bridge => { name = bridge, idx = idx } }
  node_name = "pve1"
  name      = format("vmbr1991%02d", each.value.idx)
}

resource "proxmox_virtual_environment_vm" "devices" {
  for_each = { for idx, item in var.devices : item.name => item }

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
    file_id      = proxmox_virtual_environment_download_file.chr.id
    file_format  = "raw"
    interface    = "scsi0"
    size         = 10
    iothread     = true
    ssd          = true
    discard      = "on"
  }

  # OOB Management
  network_device {
    bridge  = "vmbr0"
    vlan_id = 1991
  }

  dynamic "network_device" {
    for_each = local.devices_interfaces_generated[each.key]
    iterator = ifce

    content {
      bridge  = ifce.value["bridge"]
      vlan_id = ifce.value["vlan_id"]
    }
  }
}

resource "terraform_data" "initial_provisioning" {
  for_each = { for idx, item in var.devices : item.name => item }

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
