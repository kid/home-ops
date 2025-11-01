locals {
  input_rules = concat(
    [
      {
        action           = "accept"
        connection_state = "established,related,untracked"
      },
      {
        comment      = "Allow everything on OOB Port"
        action       = "accept"
        in_interface = var.oob_mgmt_interface
      },
    ],
    [
      for idx, vlan in var.vlans :
      {
        action       = "jump"
        jump_target  = "input-${vlan.name}"
        in_interface = vlan.name
      }
    ],
    [
      {
        comment = "drop everything else",
        action  = "drop",
        log     = true
      }
    ],
  )

  forward_rules = concat(
    [
      {
        action           = "fasttrack-connection"
        connection_state = "established,related"
        hw_offload       = true
      },
      {
        id               = "accept established,related,untracked"
        action           = "accept"
        connection_state = "established,related"
      },
      {

        action           = "drop"
        connection_state = "invalid"
      },
    ],
    [
      for idx, vlan in var.vlans : {
        action       = "jump"
        jump_target  = "forward-${vlan.name}"
        in_interface = vlan.name
      }
    ],
    [
      {
        comment          = "Drop bad forward IPs"
        action           = "drop",
        src_address_list = "no_forward_ipv4"
      },
      {
        comment          = "Drop bad forward IPs"
        action           = "drop",
        src_address_list = "no_forward_ipv4"
      },
      { action = "drop", log = true },
    ],
  )

  vlans_rules = flatten([
    for _, vlan in var.vlans : [
      [
        {
          comment  = "Allow ICMP from ${vlan.name}"
          chain    = "input-${vlan.name}"
          action   = "accept"
          protocol = "icmp"
        },
        {
          comment     = "Allow DNS over TCP from ${vlan.name}"
          chain       = "input-${vlan.name}"
          action      = "accept"
          protocol    = "tcp"
          port        = 53
          dst_address = module.dhcp_server[vlan.name].gateway
        },
        {
          comment     = "Allow DNS over UDP from ${vlan.name}"
          chain       = "input-${vlan.name}"
          action      = "accept"
          protocol    = "udp"
          port        = 53
          dst_address = module.dhcp_server[vlan.name].gateway
        },
        {
          comment     = "Allow DHCP on ${vlan.name}"
          chain       = "input-${vlan.name}"
          action      = "accept"
          protocol    = "udp"
          dst_port    = 67
          dst_address = module.dhcp_server[vlan.name].gateway
        },
      ],
      [for _, rule in lookup(var.vlans_input_rules, vlan.name, []) : merge(rule, { chain = "input-${vlan.name}" })],
      [for _, rule in lookup(var.vlans_forward_rules, vlan.name, []) : merge(rule, { chain = "forward-${vlan.name}" })],
    ]
  ])


  rules = concat(
    [for _, rule in local.input_rules : merge({ chain = "input" }, rule)],
    [for _, rule in local.forward_rules : merge({ chain = "forward" }, rule)],
    local.vlans_rules,
  )

  rules_by_chain = { for _, rule in local.rules : rule.chain => rule... }
  rules_map      = merge([for chain, rules in local.rules_by_chain : { for idx, rule in rules : format("%s-%03d", chain, idx) => rule }]...)
}

resource "routeros_ip_firewall_filter" "rules" {
  depends_on = [
    routeros_interface_list.lan,
    routeros_interface_list.wan,
    routeros_ip_firewall_addr_list.no_forward_ipv4,
  ]

  for_each = local.rules_map

  chain  = each.value.chain
  action = each.value.action

  comment            = join(": ", compact(["Managed by Terraform", lookup(each.value, "comment", null)]))
  disabled           = lookup(each.value, "disabled", false)
  connection_state   = lookup(each.value, "connection_state", null)
  in_interface       = lookup(each.value, "in_interface", null)
  out_interface      = lookup(each.value, "out_interface", null)
  in_interface_list  = lookup(each.value, "in_interface_list", null)
  out_interface_list = lookup(each.value, "out_interface_list", null)
  protocol           = lookup(each.value, "protocol", null)
  dst_port           = lookup(each.value, "dst_port", null)
  src_port           = lookup(each.value, "src_port", null)
  src_address        = lookup(each.value, "src_address", null)
  dst_address        = lookup(each.value, "dst_address", null)
  src_address_list   = lookup(each.value, "src_address_list", null)
  dst_address_list   = lookup(each.value, "dst_address_list", null)
  jump_target        = lookup(each.value, "jump_target", null)
  hw_offload         = lookup(each.value, "hw_offload", null)
  log                = lookup(each.value, "log", false)

  lifecycle {
    create_before_destroy = true
  }
}

resource "routeros_move_items" "firewall_rules" {
  resource_path = "/ip/firewall/filter"
  sequence      = [for idx, _ in local.rules_map : routeros_ip_firewall_filter.rules[idx].id]
}
