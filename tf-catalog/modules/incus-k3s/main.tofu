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
    address = string
    # Extra NICs, keyed by a networks key.
    extra_nics = optional(map(object({ mac = optional(string) })), {})
  }))
}

variable "networks" {
  description = "Incus bridges to create, each tagging one VLAN on a parent NIC. Every node's first NIC is on the `k3s` one; extra_nics use the other keys."
  type = map(object({
    name    = string
    parent  = string
    vlan_id = number
    mtu     = optional(number)
  }))
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
  # The images: cloud variants ship without an SSH server.
  cloud_init_user_data = "#cloud-config\n${yamlencode({
    disable_root = false
    packages     = ["openssh-server"]
    users = [{
      name                = "root"
      ssh_authorized_keys = var.ssh_authorized_keys
    }]
  })}"

  # A GC root in the working directory, outside the repo.
  kexec_installer = "${abspath(path.root)}/.kexec-installer"
}

resource "incus_network" "this" {
  for_each = var.networks

  name = each.value.name
  type = "bridge"

  config = merge(
    {
      "bridge.external_interfaces" = "vlan${each.value.vlan_id}/${each.value.parent}/${each.value.vlan_id}"
      "ipv4.address"               = "none"
      "ipv6.address"               = "none"
    },
    each.value.mtu != null ? { "bridge.mtu" = tostring(each.value.mtu) } : {}
  )
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

resource "incus_instance" "k3s" {
  for_each = var.nodes

  name  = each.key
  image = incus_image.base.fingerprint
  type  = "virtual-machine"

  config = {
    "limits.cpu"           = each.value.cpu
    "limits.memory"        = each.value.memory
    "cloud-init.user-data" = local.cloud_init_user_data
    # The installed system boots an unsigned systemd-boot.
    "security.secureboot" = "false"
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

  # The image and its cloud-init only matter at creation: nixos-anywhere
  # replaces the system, and `deploy <host>` updates it after that.
  lifecycle {
    ignore_changes = [image, config["cloud-init.user-data"]]
  }

  device {
    name = "eth0"
    type = "nic"
    properties = merge(
      { network = incus_network.this["k3s"].name },
      each.value.mac != null ? { hwaddr = each.value.mac } : {}
    )
  }

  dynamic "device" {
    for_each = each.value.extra_nics

    content {
      name = device.key
      type = "nic"
      properties = merge(
        { network = incus_network.this[device.key].name },
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
}

# A new id each time the instance is replaced: the install module's only
# trigger, so a NixOS change never reinstalls a node.
resource "terraform_data" "install_id" {
  for_each = var.nodes

  lifecycle {
    replace_triggered_by = [incus_instance.k3s[each.key]]
  }
}

# Before each install: build the kexec installer (nixos-anywhere's default
# one is older than this flake's nixpkgs, which disko needs, see
# modules/flake/kexec-installer.nix), then wait for the base image to boot
# and run cloud-init. Its output is the install id, so each install depends
# on its own node only and `-target` can pick one node.
resource "terraform_data" "prepare_install" {
  for_each = var.nodes

  input = terraform_data.install_id[each.key].id

  provisioner "local-exec" {
    command = "nix build '${data.external.repo_root.result.path}#kexec-installer' --out-link '${local.kexec_installer}'"
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/wait-for-ssh.sh root@${each.value.address}"
  }
}

module "install" {
  source   = "github.com/nix-community/nixos-anywhere//terraform/install?ref=1.13.0"
  for_each = var.nodes

  target_host        = each.value.address
  instance_id        = terraform_data.prepare_install[each.key].output
  flake              = "${data.external.repo_root.result.path}#${each.value.nixos_attr}"
  kexec_tarball_url  = "${local.kexec_installer}/nixos-kexec-installer-noninteractive-x86_64-linux.tar.gz"
  extra_files_script = "${path.module}/scripts/host-files.sh"
  extra_environment = {
    HOST      = each.key
    REPO_ROOT = data.external.repo_root.result.path
  }
}
