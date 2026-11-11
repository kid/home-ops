# One NixOS VM on one Incus remote, attached to an existing host bridge and
# installed by nixos-anywhere. The instance and install chain of
# ../incus-k3s, for a single VM; reuses its scripts.
terraform {
  required_providers {
    incus = {
      source  = "lxc/incus"
      version = "~> 1.0"
    }
  }
}

variable "name" {
  description = "Incus instance name, and the den host it installs."
  type        = string
}

variable "remote" {
  description = "Incus remote the VM runs on."
  type        = string
}

variable "nixos_attr" {
  description = "nixosConfigurations attribute nixos-anywhere installs."
  type        = string
}

variable "cpu" {
  description = "limits.cpu."
  type        = number
}

variable "memory" {
  description = "limits.memory."
  type        = string
}

variable "disk_size" {
  description = "Root disk size."
  type        = string
}

variable "mac" {
  description = "eth0's MAC address (the den.devices one, for its static lease)."
  type        = string
}

variable "address" {
  description = "The VM's den.devices address: nixos-anywhere connects to it."
  type        = string
}

variable "bridge" {
  description = "The remote host's networkd bridge eth0 attaches to (den.devices vmBridges)."
  type        = string
}

variable "storage_pool" {
  description = "Existing Incus storage pool for the root disk."
  type        = string
}

variable "base_image" {
  description = "Image the VM boots before nixos-anywhere replaces it."
  type        = string
  default     = "images:debian/13/cloud"
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

data "external" "repo_root" {
  program = ["${path.module}/../incus-k3s/scripts/repo-root.sh"]
}

resource "incus_instance" "this" {
  remote = var.remote
  name   = var.name
  image  = var.base_image
  type   = "virtual-machine"

  config = {
    "limits.cpu"           = var.cpu
    "limits.memory"        = var.memory
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
      size = var.disk_size
    }
  }

  device {
    name = "eth0"
    type = "nic"
    properties = {
      nictype = "bridged"
      parent  = var.bridge
      hwaddr  = var.mac
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

  # The image and its cloud-init only matter at creation: nixos-anywhere
  # replaces the system, and `colmena apply --on <host>` updates it after that.
  lifecycle {
    ignore_changes = [image, config["cloud-init.user-data"]]
  }
}

# A new id each time the instance is replaced: the install module's only
# trigger, so a NixOS change never reinstalls the VM. A whole-resource
# reference would also fire on any in-place update (e.g. limits.memory).
# `architecture` keeps its state value on an update and is unknown only
# when the instance is planned for (re)creation.
resource "terraform_data" "install_id" {
  lifecycle {
    replace_triggered_by = [incus_instance.this.architecture]
  }
}

# Before each install: build the kexec installer (nixos-anywhere's default
# one is older than this flake's nixpkgs, which disko needs, see
# modules/flake/kexec-installer.nix), then wait for the base image to boot
# and run cloud-init. Provisioners run only on create, and a changed `input`
# updates in place: it must also replace on a new id.
resource "terraform_data" "prepare_install" {
  triggers_replace = terraform_data.install_id.id
  input            = terraform_data.install_id.id

  provisioner "local-exec" {
    command = "nix build '${data.external.repo_root.result.path}#kexec-installer' --out-link '${local.kexec_installer}'"
  }

  provisioner "local-exec" {
    command = "${path.module}/../incus-k3s/scripts/wait-for-ssh.sh root@${var.address}"
  }
}

module "install" {
  source = "github.com/nix-community/nixos-anywhere//terraform/install?ref=1.13.0"

  target_host        = var.address
  instance_id        = terraform_data.prepare_install.output
  flake              = "${data.external.repo_root.result.path}#${var.nixos_attr}"
  kexec_tarball_url  = "${local.kexec_installer}/nixos-kexec-installer-noninteractive-x86_64-linux.tar.gz"
  extra_files_script = "${path.module}/../incus-k3s/scripts/host-files.sh"
  extra_environment = {
    HOST      = var.name
    REPO_ROOT = data.external.repo_root.result.path
  }
}
