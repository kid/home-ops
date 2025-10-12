generate "provider-proxmox" {
  path = "provider-proxmox.tf"
  if_exists = "overwrite_terragrunt"
  contents = file("provider-proxmox.tf")
}
