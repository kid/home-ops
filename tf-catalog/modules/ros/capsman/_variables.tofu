variable "capsman_interfaces" {
  description = "List of interfaces (lists) on which CAPsMAN will listen for CAP connections."
  type        = list(string)
}

variable "bridge_name" {
  description = "Name of the bridge defined on the CAP devices."
  type        = string
}

variable "passphrase_groups" {
  description = "Map of passphrase groups for different SSIDs and VLANs."
  type = map(object({
    vlan_id  = number
    isolated = optional(bool, false)
  }))
}
