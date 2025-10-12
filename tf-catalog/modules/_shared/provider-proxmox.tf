variable "proxmox_endpoint" {
  type        = string
  description = "The URL of the proxmox server."
}

variable "proxmox_username" {
  type        = string
  description = "The username for accessing the proxmox server."
}

variable "proxmox_password" {
  type        = string
  sensitive   = true
  description = "The password for accessing the proxmox server."
}

variable "proxmox_insecure" {
  type        = bool
  default     = false
  description = "Whether to skip TLS certificate verification when connecting to the proxmox server."
}

provider "proxmox" {
  endpoint = var.proxmox_endpoint
  username = var.proxmox_username
  password = var.proxmox_password
  insecure = var.proxmox_insecure
}
