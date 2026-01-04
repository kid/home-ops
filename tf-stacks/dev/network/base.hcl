locals {
  env_cfg     = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  devices_cfg = read_terragrunt_config(find_in_parent_folders("lab/devices.hcl")).locals

  vlans = local.env_cfg.vlans

  shared_inputs = {
    bridge_name         = "bridge1"
    mgmt_interface_list = local.env_cfg.interface_lists.MANAGEMENT
  }

  devices_augmented = [
    for dev_idx, dev in local.devices_cfg.devices : merge({
      hostname          = dev.name
      routeros_endpoint = [for _, ifce in dev.interfaces : ifce.ip_address if try(ifce.ip_address, null) != null][0]
      vlans = {
        for vlan_name, vlan in local.vlans : vlan_name => merge(
          vlan,
          # (dev.name == "router" || vlan_name == local.vlans.Management.name) ? {
          #   ip_address = "${cidrhost(vlan.cidr, dev_idx + 1)}/${vlan.prefix}"
          # } : {},
        )
        if !startswith(dev.name, "client") && !startswith(dev.name, "trusted")
      }
      ip_addresses = startswith(dev.name, "client") || startswith(dev.name, "trusted") ? {} : {
        for _, vlan in local.vlans : vlan.name => "${cidrhost(vlan.cidr, dev_idx + 1)}/${vlan.prefix}"
        if dev.name == "router" || vlan.name == local.vlans.Management.name
      }
    })
  ]

  # inputs specific to the routeros base module
  per_device_inputs = {
    for idx, dev in local.devices_augmented : dev.hostname => merge(
      dev,
      {
        mgmt_interface_list = local.env_cfg.interface_lists.MANAGEMENT

        certificate_unit = local.env_cfg.environment
        certificate_alt_names = concat(
          formatlist("DNS:%s", compact([dev.hostname, try("${dev.hostname}.${dev.vlans.Management.domain}", null)])),
          formatlist("IP:%s", compact([dev.routeros_endpoint, try(split("/", dev.ip_addresses[local.vlans.Management.name])[0], null)])),
        )
      }
    )
  }
}
