variable "cluster_name" {
  type        = string
  description = "Name of the Talos cluster"
  default     = "talos-cluster"
}

variable "nodes" {
  type = map(object({
    ip_address   = string
    vm_id        = optional(number)
    node_name    = optional(string)
    cpu_cores    = optional(number)
    memory       = optional(number)
    disk_size    = optional(number)
    datastore_id = optional(string)
  }))
  description = "Map of Talos nodes to create. Key is the node name suffix."
}

variable "node_name" {
  type        = string
  description = "Default Proxmox node name to deploy VMs on"
  default     = "pve1"
}

variable "talos_version" {
  type        = string
  description = "Talos Linux version"
  default     = "v1.12.2"
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version"
  default     = "1.32.0"
}

variable "talos_image_datastore" {
  type        = string
  description = "Proxmox datastore to store the Talos image"
  default     = "local"
}

variable "cpu_cores" {
  type        = number
  description = "Default number of CPU cores for VMs"
  default     = 2
}

variable "memory" {
  type        = number
  description = "Default memory in MB for VMs"
  default     = 4096
}

variable "disk_size" {
  type        = number
  description = "Default disk size in GB for VMs"
  default     = 32
}

variable "datastore_id" {
  type        = string
  description = "Default Proxmox datastore ID for VM disks"
  default     = "local-zfs"
}

variable "network_bridge" {
  type        = string
  description = "Network bridge for the VMs"
  default     = "vmbr0"
}

variable "dhcp_server" {
  type        = string
  description = "RouterOS DHCP server name for static leases"
}

variable "dhcp_dns_zone" {
  type        = string
  description = "DNS zone to append to DHCP lease names"
  default     = null
}

variable "vlan_id" {
  type        = number
  description = "VLAN ID for the network interface"
  default     = null
}

variable "schematic_customizations" {
  type = object({
    system_extensions = optional(list(string), [])
  })
  description = "Talos schematic customizations"
  default = {
    system_extensions = ["qemu-guest-agent"]
  }
}

variable "tags" {
  type        = list(string)
  description = "Tags to apply to the VMs"
  default     = ["terraform", "talos"]
}

# BGP Configuration {{{

variable "bgp_enabled" {
  type        = bool
  description = "Enable BGP peering between RouterOS and Talos nodes"
  default     = false
}

variable "bgp_local_asn" {
  type        = number
  description = "Local ASN for the RouterOS BGP instance"
  default     = 64512
}

variable "bgp_remote_asn" {
  type        = number
  description = "Remote ASN for the Talos/Cilium BGP peers"
  default     = 64513
}

variable "bgp_router_id" {
  type        = string
  description = "Router ID for BGP instance (typically router's IP on the Talos VLAN)"
  default     = null
}

# }}}
