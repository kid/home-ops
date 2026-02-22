locals {
  infra_module_version   = "talos-infra-v1.0.0"
  secrets_module_version = "talos-secrets-v1.0.1"

  vlan_id   = 40
  vlan_cidr = "10.0.${local.vlan_id}.0/24"

  dhcp_dns_zone = "talos.home.kidibox.net"

  nodes = {
    for idx in range(1, 4) : "talos-cp-${idx}" => {
      vm_id = local.vlan_id * 1000 + idx + 10
      ip_address = "10.0.${local.vlan_id}.${idx + 10}"
      cpu_cores  = 4
    }
  }

  nodes_fqdns = [
    for name, node in local.nodes : "${name}.${local.dhcp_dns_zone}"
  ]

  op_vault = "home-ops"
}

unit "infra" {
  source = "git::git@github.com:kid/terragrunt-infra-catalog//units/talos-infra?ref=${local.infra_module_version}"
  path   = "infra"

  values = {
    version = local.infra_module_version

    op_vault         = local.op_vault
    op_item_proxmox  = "pve1"
    op_item_routeros = "rb5009"

    cluster_name  = "prd"
    talos_version = "v1.12.3"

    dhcp_server   = "Talos"
    dhcp_dns_zone = local.dhcp_dns_zone
    vlan_id       = 40

    nodes = local.nodes

    bgp_enabled    = true
    bgp_local_asn  = 64512
    bgp_remote_asn = 64513
    bgp_router_id  = "10.0.40.1"
  }
}

unit "secrets" {
  source = "git::git@github.com:kid/terragrunt-infra-catalog//units/talos-secrets?ref=${local.secrets_module_version}"
  path   = "secrets"

  values = {
    version = local.secrets_module_version

    cluster_name    = "prd"
    talos_nodes     = local.nodes_fqdns
    talos_endpoints = local.nodes_fqdns

    op_vault = local.op_vault
    op_item  = "talos"
  }
}
