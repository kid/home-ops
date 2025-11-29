generate "provider_proxmox" {
  path      = "provider_proxmox.tofu"
  if_exists = "overwrite_terragrunt"
  contents  = file("provider-proxmox.tofu")
}
