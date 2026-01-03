variable "capsman_interfaces" {
  description = "List of interfaces (lists) on which CAPsMAN will listen for CAP connections."
  type        = list(string)
}

variable "bridge_name" {
  description = "Name of the bridge defined on the CAP devices."
  type        = string
}
