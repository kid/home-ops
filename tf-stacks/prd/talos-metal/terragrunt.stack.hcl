locals {
  infra_module_version   = "talos-infra-v1.4.0"
  secrets_module_version = "talos-secrets-v1.0.1"

  config = yamldecode(file("${get_repo_root()}/clusters/metal/talos/config.yaml"))

  vlan_id   = 40
  vlan_cidr = "10.0.${local.vlan_id}.0/24"

  dhcp_dns_zone = "talos.home.kidibox.net"

  nodes = {
    for idx, node in local.config.nodes : node.hostname => {
      vm_id      = local.vlan_id * 1000 + 10 + idx
      ip_address = node.ipAddress
      cpu_cores  = 4
      memory     = 8192
      disk_size  = 100
    } if lookup(node, "target", local.config.target) != "metal"
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

    cluster_name  = local.config.clusterName
    talos_version = local.config.talosVersion

    dhcp_server   = "Talos"
    dhcp_dns_zone = local.dhcp_dns_zone
    vlan_id       = 40

    nodes = local.nodes

    image_factory_schematic = yamldecode(file("${get_repo_root()}/clusters/metal/talos/nodes/talos1.schematic.yaml"))
  }
}
