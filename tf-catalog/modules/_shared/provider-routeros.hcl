generate "provider-routeros" {
  path      = "provider-routeros.tf"
  if_exists = "overwrite_terragrunt"
  contents  = file("provider-routeros.tf")
}
