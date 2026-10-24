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

variable "extra_networks" {
  description = "More VLAN-tagged Incus bridges, keyed like a node's extra_nics."
  type = map(object({
    name    = string
    parent  = string
    vlan_id = number
    mtu     = optional(number)
  }))
  default = {}
}

variable "nodes" {
  description = "Passed through to incus-k3s, which owns the type."
  type        = any
}

variable "storage_pool" {
  type = string
}

variable "ssh_authorized_keys" {
  type = list(string)
}

module "network" {
  source = "../incus-vlan-networks"

  networks = merge(var.extra_networks, { k3s = var.network })
}

module "nodes" {
  source = "../incus-k3s"

  nodes               = var.nodes
  network_name        = module.network.network_names.k3s
  network_names       = module.network.network_names
  storage_pool        = var.storage_pool
  ssh_authorized_keys = var.ssh_authorized_keys
}
