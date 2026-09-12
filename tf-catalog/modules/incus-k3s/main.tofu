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
  }))
}

variable "network_name" {
  description = "Existing Incus network for node NICs."
  type        = string
}

variable "storage_pool" {
  description = "Existing Incus storage pool for node root disks."
  type        = string
}

data "external" "image" {
  for_each = var.nodes

  program = ["${path.module}/scripts/build-image.sh"]

  query = {
    attr = each.value.nixos_attr
  }
}

# Lands in this stack's tfstate as plaintext — fine for a throwaway dev key,
# not for a real host's without reconsidering state handling first.
data "external" "host_key" {
  for_each = var.nodes

  program = ["${path.module}/scripts/host-key.sh"]

  query = {
    host = each.key
  }
}

locals {
  cloud_init_user_data = {
    for k, v in var.nodes : k => "#cloud-config\n${yamlencode({
      ssh_keys = {
        ed25519_private = data.external.host_key[k].result.private
        ed25519_public  = data.external.host_key[k].result.public
      }
    })}"
  }
}

resource "incus_image" "k3s" {
  for_each = var.nodes

  source_file = {
    data_path     = data.external.image[each.key].result.qcow2
    metadata_path = data.external.image[each.key].result.metadata
  }

  alias {
    name = "nixos/${each.key}"
  }
}

resource "incus_instance" "k3s" {
  for_each = var.nodes

  name  = each.key
  image = incus_image.k3s[each.key].fingerprint
  type  = "virtual-machine"

  config = {
    "limits.cpu"           = each.value.cpu
    "limits.memory"        = each.value.memory
    "cloud-init.user-data" = local.cloud_init_user_data[each.key]
  }

  device {
    name = "root"
    type = "disk"
    properties = {
      path = "/"
      pool = var.storage_pool
      size = each.value.disk_size
    }
  }

  device {
    name = "eth0"
    type = "nic"
    properties = merge(
      { network = var.network_name },
      each.value.mac != null ? { hwaddr = each.value.mac } : {}
    )
  }

  # Agent-independent cloud-init seed: no incus-agent runs in this image.
  device {
    name = "cloud-init"
    type = "disk"
    properties = {
      source = "cloud-init:config"
    }
  }
}
