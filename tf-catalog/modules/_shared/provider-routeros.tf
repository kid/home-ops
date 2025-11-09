data "external" "endpoint" {
  program = ["bash", "${path.module}/get_ros_endpoint.sh", var.routeros_endpoint]
}

variable "routeros_endpoint" {
  type        = string
  description = "The URL of the MikroTik device."
}

variable "routeros_username" {
  type        = string
  description = "The username for accessing the MikroTik device."
}

variable "routeros_password" {
  type        = string
  sensitive   = true
  description = "The password for accessing the MikroTik device."
}

variable "routeros_insecure" {
  type        = bool
  default     = false
  description = "Whether to skip TLS certificate verification when connecting to the MikroTik device."
}

provider "routeros" {
  hosturl  = data.external.endpoint.result["endpoint"]
  username = var.routeros_username
  password = var.routeros_password
  insecure = var.routeros_insecure

  suppress_syso_del_warn = true
}
