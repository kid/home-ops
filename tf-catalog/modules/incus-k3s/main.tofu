terraform {
  required_providers {
    incus = {
      source  = "lxc/incus"
      version = "~> 1.0"
    }
  }
}

variable "nodes" {
  description = "k3s cluster compute nodes to run as Incus VMs, keyed by den.hosts entity name."
  type = map(object({
    nixos_attr = string
    cpu        = number
    memory     = string
    disk_size  = string
    mac        = optional(string)
    # The node's den.devices address: nixos-anywhere connects to it.
    address = optional(string)
    # false for a node made before this module installed with nixos-anywhere
    # (from a per-host image): it is never kexec'd.
    install = optional(bool, true)
    # Extra raw block devices beyond the root disk, keyed by device name.
    extra_disks = optional(map(object({ size = string })), {})
    # Extra NICs, keyed by a network_names key.
    extra_nics = optional(map(object({ mac = optional(string) })), {})
  }))
}

variable "network_name" {
  description = "Existing Incus network for node NICs."
  type        = string
}

variable "network_names" {
  description = "Existing Incus networks extra_nics refer to, by key."
  type        = map(string)
  default     = {}
}

variable "storage_pool" {
  description = "Existing Incus storage pool for node root disks."
  type        = string
}

variable "base_image" {
  description = "Image on the images: remote that a node boots before nixos-anywhere replaces it."
  type        = string
  default     = "debian/13/cloud"
}

variable "ssh_authorized_keys" {
  description = "Keys put on the base image's root account, for nixos-anywhere."
  type        = list(string)
}

locals {
  install_nodes = { for k, v in var.nodes : k => v if v.install }

  cloud_init_user_data = "#cloud-config\n${yamlencode({
    disable_root = false
    users = [{
      name                = "root"
      ssh_authorized_keys = var.ssh_authorized_keys
    }]
  })}"

  extra_disks = merge([
    for node_key, node in var.nodes : {
      for disk_key, disk in node.extra_disks :
      "${node_key}/${disk_key}" => merge(disk, { node = node_key, disk = disk_key })
    }
  ]...)
}

data "external" "repo_root" {
  program = ["${path.module}/scripts/repo-root.sh"]
}

resource "incus_image" "base" {
  source_image = {
    remote = "images"
    name   = var.base_image
    type   = "virtual-machine"
  }
}

# A plain disk device with `pool`+`size` and no `path`/`source` is only
# valid for the special-cased root disk — any other disk needs a real
# custom volume to attach as its `source`.
resource "incus_storage_volume" "extra" {
  for_each = local.extra_disks

  name         = "${each.value.node}-${each.value.disk}"
  pool         = var.storage_pool
  content_type = "block"

  config = {
    size = each.value.size
  }
}

resource "incus_instance" "k3s" {
  for_each = var.nodes

  name  = each.key
  image = incus_image.base.fingerprint
  type  = "virtual-machine"

  config = merge(
    {
      "limits.cpu"           = each.value.cpu
      "limits.memory"        = each.value.memory
      "cloud-init.user-data" = local.cloud_init_user_data
    },
    # The installed system boots an unsigned systemd-boot.
    each.value.install ? { "security.secureboot" = "false" } : {}
  )

  device {
    name = "root"
    type = "disk"
    properties = {
      path = "/"
      pool = var.storage_pool
      size = each.value.disk_size
    }
  }

  # The image only matters at creation: nixos-anywhere replaces the system,
  # and `deploy <host>` updates it after that.
  lifecycle {
    ignore_changes = [image]
  }

  device {
    name = "eth0"
    type = "nic"
    properties = merge(
      { network = var.network_name },
      each.value.mac != null ? { hwaddr = each.value.mac } : {}
    )
  }

  dynamic "device" {
    for_each = each.value.extra_nics

    content {
      name = device.key
      type = "nic"
      properties = merge(
        { network = var.network_names[device.key] },
        device.value.mac != null ? { hwaddr = device.value.mac } : {}
      )
    }
  }

  # Agent-independent cloud-init seed for the base image.
  device {
    name = "cloud-init"
    type = "disk"
    properties = {
      source = "cloud-init:config"
    }
  }

  # No `path`, so these appear as raw block devices in the guest rather
  # than mounted filesystems.
  dynamic "device" {
    for_each = each.value.extra_disks

    content {
      name = device.key
      type = "disk"
      properties = {
        pool   = var.storage_pool
        source = incus_storage_volume.extra["${each.key}/${device.key}"].name
      }
    }
  }
}

# A new id each time the instance is replaced: the install module's only
# trigger, so a NixOS change never reinstalls a node.
resource "terraform_data" "install_id" {
  for_each = local.install_nodes

  lifecycle {
    replace_triggered_by = [incus_instance.k3s[each.key]]
  }
}

# The base image needs a while to boot and run cloud-init.
resource "terraform_data" "wait_for_ssh" {
  for_each = local.install_nodes

  triggers_replace = terraform_data.install_id[each.key].id

  provisioner "local-exec" {
    command = "${path.module}/scripts/wait-for-ssh.sh root@${each.value.address}"
  }
}

module "install" {
  source   = "github.com/nix-community/nixos-anywhere//terraform/install?ref=1.13.0"
  for_each = local.install_nodes

  target_host        = each.value.address
  instance_id        = terraform_data.install_id[each.key].id
  flake              = "${data.external.repo_root.result.path}#${each.value.nixos_attr}"
  extra_files_script = "${path.module}/scripts/host-files.sh"
  extra_environment = {
    HOST      = each.key
    REPO_ROOT = data.external.repo_root.result.path
  }

  depends_on = [terraform_data.wait_for_ssh]
}
