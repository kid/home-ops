# TODO: change to ephemeral resource once Tofu 1.11 releases.
data "sops_file" "routeros_secrets" {
  source_file = var.routeros_secrets_path
}

data "external" "endpoint" {
  for_each = toset(strcontains(var.routeros_endpoint, "://") ? [] : ["self"])
  # Terragrunt's generate won't set execute flag, so we explicitely use bash here
  program = ["bash", "${path.module}/get_ros_endpoint.sh", var.routeros_endpoint]
}


variable "routeros_secrets_path" {
  type        = string
  description = "Path to the sops encrypted file containing credentials"
}

variable "routeros_endpoint" {
  type        = string
  description = "The URL of the MikroTik device."
}

variable "routeros_username" {
  type        = string
  nullable    = true
  default     = null
  description = "The username for accessing the MikroTik device. If not set, it will be taken from the secrets file"
}

variable "routeros_password" {
  type        = string
  sensitive   = true
  nullable    = true
  default     = null
  description = "The password for accessing the MikroTik device. If not set, it will be taken from the secrets file"
}

variable "routeros_insecure" {
  type        = bool
  nullable    = true
  default     = null
  description = "Whether to skip TLS certificate verification when connecting to the MikroTik device."
}

locals {
  routeros_username = coalesce(var.routeros_username, try(data.sops_file.routeros_secrets.data["routeros_username"], null))
  routeros_insecure = coalesce(var.routeros_insecure, try(data.sops_file.routeros_secrets.data["routeros_insecure"], true))
  routeros_password = coalesce(var.routeros_password, try(data.sops_file.routeros_secrets.data["users.${local.routeros_username}.password"], null))
}

provider "routeros" {
  hosturl  = strcontains(var.routeros_endpoint, "://") ? var.routeros_endpoint : data.external.endpoint["self"].result["endpoint"]
  insecure = local.routeros_insecure
  username = local.routeros_username
  password = local.routeros_password

  # Yes, I know system objects are only removed from the path
  suppress_syso_del_warn = true
}
