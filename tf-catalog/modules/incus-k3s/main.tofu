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
    # The Incus remote (a var.remotes key) the VM runs on.
    remote     = string
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

variable "remotes" {
  description = "Incus hosts that can run nodes, keyed by provider remote name."
  type = map(object({
    # The NIC carrying the VLANs: Incus creates every network there. null:
    # the host's own networkd has bridges of the networks' names (den.devices
    # vmBridges), which nodes attach to as bridged NICs.
    parent = optional(string)
  }))
}

variable "networks" {
  description = "VLAN bridges, created on remotes with a parent NIC. Every node's first NIC is on the `k3s` one; extra_nics use the other keys."
  type = map(object({
    name    = string
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

  remote_networks = merge([
    for remote_name, remote in var.remotes : {
      for key, network in var.networks : "${remote_name}/${key}" => merge(network, {
        remote = remote_name
        parent = remote.parent
      })
    } if remote.parent != null
  ]...)

  # A node's NIC on a network: the Incus network, or the host's bridge of
  # the same name. incus_instance depends on incus_network for the former.
  nic = {
    for name, node in var.nodes : name => {
      for key, network in var.networks : key => (
        var.remotes[node.remote].parent != null
        ? tomap({ network = network.name })
        : tomap({ nictype = "bridged", parent = network.name })
      )
    }
  }
}

moved {
  from = incus_network.this["k3s"]
  to   = incus_network.this["node1/k3s"]
}

moved {
  from = incus_network.this["storage"]
  to   = incus_network.this["node1/storage"]
}

moved {
  from = incus_image.base
  to   = incus_image.base["node1"]
}

resource "incus_network" "this" {
  for_each = local.remote_networks

  remote = each.value.remote
  name   = each.value.name
  type   = "bridge"

  config = merge(
    {
      "bridge.external_interfaces" = "vlan${each.value.vlan_id}/${each.value.parent}/${each.value.vlan_id}"
      "ipv4.address"               = "none"
      "ipv6.address"               = "none"
    },
    each.value.mtu != null ? { "bridge.mtu" = tostring(each.value.mtu) } : {}
  )

  # Resources created before var.remotes have no remote in state (the
  # provider's default_remote); setting one would replace them.
  lifecycle {
    ignore_changes = [remote]
  }
}

data "external" "repo_root" {
  program = ["${path.module}/scripts/repo-root.sh"]
}

resource "incus_image" "base" {
  for_each = var.remotes

  remote = each.key
  source_image = {
    remote = "images"
    name   = var.base_image
    type   = "virtual-machine"
  }

  lifecycle {
    ignore_changes = [remote]
  }
}

resource "incus_instance" "k3s" {
  for_each = var.nodes

  remote = each.value.remote
  name   = each.key
  image  = incus_image.base[each.value.remote].fingerprint
  type   = "virtual-machine"

  depends_on = [incus_network.this]

  config = {
    "limits.cpu"           = each.value.cpu
    "limits.memory"        = each.value.memory
    "cloud-init.user-data" = local.cloud_init_user_data
    # The installed system boots an unsigned systemd-boot.
    "security.secureboot" = "false"
    # Incus force-stops a VM 30s after asking it to shut down when its host
    # stops; the guest's kubelet takes up to its 180s grace period to stop
    # its pods (modules/nixos/services/k3s/node-base.nix), then systemd stops
    # the rest.
    "boot.host_shutdown_timeout" = "240"
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
  # replaces the system, and `colmena apply --on <host>` updates it after that.
  # A remote change never recreates a node: move it with `incus move`, then
  # re-import it from its new remote (`tofu state rm`, `tofu import`).
  lifecycle {
    ignore_changes = [image, remote, config["cloud-init.user-data"]]
  }

  device {
    name = "eth0"
    type = "nic"
    properties = merge(
      local.nic[each.key]["k3s"],
      each.value.mac != null ? { hwaddr = each.value.mac } : {}
    )
  }

  dynamic "device" {
    for_each = each.value.extra_nics

    content {
      name = device.key
      type = "nic"
      properties = merge(
        local.nic[each.key][device.key],
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
# trigger, so a NixOS change never reinstalls a node. A whole-resource
# reference would also fire on any in-place update (e.g. limits.memory).
# `architecture` keeps its state value on an update and is unknown only
# when the instance is planned for (re)creation.
resource "terraform_data" "install_id" {
  for_each = var.nodes

  lifecycle {
    replace_triggered_by = [incus_instance.k3s[each.key].architecture]
  }
}

# Before each install: build the kexec installer (nixos-anywhere's default
# one is older than this flake's nixpkgs, which disko needs, see
# modules/flake/kexec-installer.nix), then wait for the base image to boot
# and run cloud-init. Its output is the install id, so each install depends
# on its own node only and `-target` can pick one node. Provisioners run
# only on create, and a changed `input` updates in place: it must also
# replace on a new id.
resource "terraform_data" "prepare_install" {
  for_each = var.nodes

  triggers_replace = terraform_data.install_id[each.key].id
  input            = terraform_data.install_id[each.key].id

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
