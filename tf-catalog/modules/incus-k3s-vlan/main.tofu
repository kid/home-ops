terraform {
  required_providers {
    incus = {
      source  = "lxc/incus"
      version = "~> 1.0"
    }
  }
}

variable "network" {
  description = "The VLAN-tagged Incus bridge the k3s nodes attach to."
  type = object({
    name    = string
    parent  = string
    vlan_id = number
  })
}

variable "nodes" {
  description = "Passed through to incus-k3s, which owns the type."
  type        = any
}

variable "storage_pool" {
  type = string
}

module "network" {
  source = "../incus-vlan-networks"

  networks = { k3s = var.network }
}

module "nodes" {
  source = "../incus-k3s"

  nodes        = var.nodes
  network_name = module.network.network_names.k3s
  storage_pool = var.storage_pool
}
