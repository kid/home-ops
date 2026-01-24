terraform {
  required_version = ">= 1.8.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.93.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.10.0"
    }
    routeros = {
      source  = "terraform-routeros/routeros"
      version = "1.99.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = "1.3.0"
    }
    macaddress = {
      source  = "ivoronin/macaddress"
      version = "0.3.0"
    }
  }
}
