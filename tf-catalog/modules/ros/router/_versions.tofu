terraform {
  required_version = ">= 1.10"

  required_providers {
    routeros = {
      source  = "terraform-routeros/routeros"
      version = "1.95.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = "1.3.0"
    }
  }
}
