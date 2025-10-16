resource "proxmox_virtual_environment_container" "containers" {
  depends_on = [
    proxmox_virtual_environment_network_linux_bridge.ports,
    proxmox_virtual_environment_vm.devices,
  ]
  for_each     = { for idx, item in var.devices : item.name => item if item.type != "chr" }
  vm_id        = local.devices_vm_ids[each.key]
  tags         = local.tags
  node_name    = "pve1"
  unprivileged = true

  disk {
    datastore_id = "local-zfs"
    size         = 10
  }

  operating_system {
    # template_file_id = proxmox_virtual_environment_download_file.images[each.value.type].id
    # template_file_id = "local:vztmpl/ubuntu-25.04-standard_25.04-1.1_amd64.tar.zst"
    # template_file_id = "local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst"
    template_file_id = "local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst"
    type             = each.value.type
  }

  dynamic "network_interface" {
    for_each = try(local.devices_interfaces_generated[each.key], {})
    iterator = ifce

    content {
      name    = "veth${each.count}"
      bridge  = ifce.value["bridge"]
      vlan_id = ifce.value["vlan_id"]
    }
  }

  dynamic "initialization" {
    for_each = toset(each.value.type == "debian" ? ["enabled"] : [])

    content {
      hostname = "lab-${each.key}"

      user_account {
        password = var.ssh_password
        keys     = [for _, key in var.ssh_keys : trimspace(key)]
      }
    }
  }
}
