terraform {
  required_version = ">= 1.10"

  required_providers {
    external = {
      source  = "hashicorp/external"
      version = "2.3.5"
    }
    routeros = {
      source  = "terraform-routeros/routeros"
      version = "1.97.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = "1.3.0"
    }
  }
}
