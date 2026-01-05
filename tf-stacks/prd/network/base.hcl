locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals

  shared_inputs = {
    bridge_name = "bridge1"

    dns_upstream_servers = local.env_cfg.dns_upstream_servers
    mgmt_interface_list  = local.env_cfg.interface_lists.MANAGEMENT
    wan_interface_list   = local.env_cfg.interface_lists.WAN

    vlans = {
      Management = local.env_cfg.vlans.Management
    }
  }
}
