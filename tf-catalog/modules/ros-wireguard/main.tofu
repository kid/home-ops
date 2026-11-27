# WireGuard remote access on a RouterOS device, plus the IP Cloud DDNS name
# clients use as the endpoint. Neither catalog has an equivalent module.
terraform {
  required_providers {
    onepassword = {
      source  = "1Password/onepassword"
      version = "~> 3.0"
    }
    routeros = {
      source  = "terraform-routeros/routeros"
      version = "~> 1.99"
    }
  }
}

variable "op_vault" {
  type = string
}

variable "op_item_routeros" {
  type = string
}

variable "routeros_insecure" {
  type    = bool
  default = true
}

variable "interface_name" {
  type = string
}

variable "listen_port" {
  type = number
}

variable "address" {
  type        = string
  description = "Router address on the tunnel, in CIDR notation"
}

variable "interface_list" {
  type = string
}

variable "peers" {
  type = map(object({
    public_key = string
    address    = string
  }))
  default     = {}
  description = "Peers keyed by name, each with a single tunnel address"
}

provider "onepassword" {}

data "onepassword_item" "routeros" {
  vault = var.op_vault
  title = var.op_item_routeros
}

provider "routeros" {
  hosturl  = data.onepassword_item.routeros.url
  username = data.onepassword_item.routeros.username
  password = data.onepassword_item.routeros.password
  insecure = var.routeros_insecure

  suppress_syso_del_warn = true
}

resource "routeros_interface_wireguard" "this" {
  name        = var.interface_name
  listen_port = var.listen_port
  mtu         = "1420"
}

resource "routeros_ip_address" "this" {
  address   = var.address
  interface = routeros_interface_wireguard.this.name
}

resource "routeros_interface_list_member" "this" {
  interface = routeros_interface_wireguard.this.name
  list      = var.interface_list
}

resource "routeros_interface_wireguard_peer" "this" {
  for_each = var.peers

  interface       = routeros_interface_wireguard.this.name
  public_key      = each.value.public_key
  allowed_address = ["${each.value.address}/32"]
  comment         = each.key
  is_responder    = true
}

resource "routeros_ip_cloud" "this" {
  ddns_enabled = "yes"
  update_time  = "false"
}

output "public_key" {
  value = routeros_interface_wireguard.this.public_key
}

output "ip_cloud_dns_name" {
  value = routeros_ip_cloud.this.dns_name

  precondition {
    condition     = routeros_ip_cloud.this.dns_name != null && routeros_ip_cloud.this.dns_name != ""
    error_message = "IP Cloud has not registered a DNS name yet; re-run apply in a minute."
  }
}
