variable "ros_endpoint" {
  type        = string
  description = "The URL of the MikroTik device."
}

variable "ros_username" {
  type        = string
  description = "The username for accessing the MikroTik device."
}

variable "ros_password" {
  type        = string
  sensitive   = true
  description = "The password for accessing the MikroTik device."
}

variable "ros_insecure" {
  type        = bool
  default     = false
  description = "Whether to skip TLS certificate verification when connecting to the MikroTik device."
}

provider "routeros" {
  hosturl  = var.ros_endpoint
  username = var.ros_username
  password = var.ros_password
  insecure = var.ros_insecure
}
