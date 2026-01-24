output "schematic_id" {
  description = "The Talos image factory schematic ID"
  value       = talos_image_factory_schematic.this.id
}

output "schematic_yaml" {
  description = "The Talos image factory schematic YAML"
  value       = talos_image_factory_schematic.this.schematic
}

output "nodes" {
  description = "Map of node information"
  value = {
    for name, node in local.nodes : name => {
      vm_id       = proxmox_virtual_environment_vm.nodes[name].vm_id
      vm_name     = proxmox_virtual_environment_vm.nodes[name].name
      ip_address  = node.ip_address
      mac_address = macaddress.nodes[name].address
    }
  }
}

output "talos_image_url" {
  description = "The Talos disk image URL from the image factory"
  value       = data.talos_image_factory_urls.this.urls.disk_image
}
