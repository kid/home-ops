locals {
  interface_lists = toset(concat(
    flatten([for _, ifce in var.ethernet_interfaces : ifce.interface_lists]),
    flatten([for _, vlan in var.vlans : vlan.interface_lists]),
  ))

  interface_lists_members = {
    for list_name in local.interface_lists : list_name => concat(
      [for ifce_name, ifce in var.ethernet_interfaces : ifce_name if contains(ifce.interface_lists, list_name)],
      [for vlan_name, vlan in var.vlans : vlan_name if contains(vlan.interface_lists, list_name)],
    )
  }

  members_final = merge([
    for list_name, members in local.interface_lists_members : {
      for _, member in members : format("%s-%s", list_name, member) => { list = list_name, interface = member }
    }
  ]...)
}

resource "routeros_interface_list" "lists" {
  for_each = local.interface_lists
  name     = each.value
}

resource "routeros_interface_list_member" "lists_members" {
  depends_on = [
    routeros_interface_list.lists,
    routeros_interface_ethernet.ethernet,
    routeros_interface_vlan.vlans,
  ]

  for_each  = local.members_final
  interface = each.value.interface
  list      = each.value.list
}
