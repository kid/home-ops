locals {
  env_cfg                 = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  routeros_shared_secrets = yamldecode(sops_decrypt_file("${get_repo_root()}/secrets/routeros.sops.yaml"))
  routeros_secrets        = yamldecode(sops_decrypt_file("${get_repo_root()}/secrets/${local.env_cfg.environment}/routeros.sops.yaml"))
  devices_cfg             = read_terragrunt_config(find_in_parent_folders("lab/devices.hcl")).locals

  vlans = local.env_cfg.vlans

  users = {
    for name, user in local.routeros_shared_secrets.users :
    name => {
      group = user.group
      keys  = user.ssh_keys
    }
  }

  passwords = { for name, user in local.routeros_shared_secrets.users : name => user.password }

  devices_augmented = [
    for dev_idx, dev in local.devices_cfg.devices : merge({
      hostname          = dev.name
      routeros_endpoint = [for _, ifce in dev.interfaces : ifce.ip_address if try(ifce.ip_address, null) != null][0]
      vlans = {
        for vlan_name, vlan in local.vlans : vlan_name => merge(
          vlan,
          (dev.name == "router" || vlan_name == local.vlans.Management.name) ? {
            ip_address = "${cidrhost(vlan.cidr, dev_idx + 1)}/${vlan.prefix}"
          } : {},
        )
        if !startswith(dev.name, "client") && !startswith(dev.name, "trusted")
      }
    })
  ]

  # inputs specific to the routeros base module
  per_device_inputs = {
    for idx, dev in local.devices_augmented : dev.hostname => merge(
      dev,
      local.routeros_secrets,
      {
        users     = local.users
        passwords = local.passwords

        mgmt_interface_list = local.env_cfg.interface_lists.MANAGEMENT

        certificate_unit = local.env_cfg.environment
        certificate_alt_names = concat(
          formatlist("DNS:%s", compact([dev.hostname, try("${dev.hostname}.${dev.vlans.Management.domain}", null)])),
          formatlist("IP:%s", compact([dev.routeros_endpoint, try(split("/", dev.vlans.Management.ip_address)[0], null)])),
        )
      }
    )
  }
}
