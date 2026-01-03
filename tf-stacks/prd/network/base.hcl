locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals

  shared_inputs = {
    bridge_name        = "bridge1"
    mgmt_interface_list = local.env_cfg.interface_lists.MANAGEMENT
    vlans               = local.env_cfg.vlans
  }
}
