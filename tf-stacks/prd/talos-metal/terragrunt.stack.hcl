locals {
  infra_module_version = "talos-infra-v1.4.0"
  bgp_module_version   = "talos-bgp-v1.1.0"

  config = yamldecode(file("${get_repo_root()}/clusters/metal/talos/config.yaml"))

  vlan_id   = 40
  vlan_cidr = "10.0.${local.vlan_id}.0/24"

  dhcp_dns_zone = "talos.home.kidibox.net"


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
    vlan_id       = local.vlan_id

    nodes = {
      for idx, node in local.config.nodes : node.hostname => {
        vm_id      = local.vlan_id * 1000 + 10 + idx
        ip_address = node.ipAddress
        cpu_cores  = 4
        memory     = 8192
        disk_size  = 100
        additional_disks = [
          { size = 32 },
          { size = 32 },
        ]
      } if lookup(node, "target", local.config.target) != "metal"
    }

    image_factory_schematic = yamldecode(file("${get_repo_root()}/clusters/metal/talos/nodes/talos1.schematic.yaml"))
  }
}

unit "bgp" {
  source = "git::git@github.com:kid/terragrunt-infra-catalog//units/talos-bgp?ref=${local.bgp_module_version}"
  path   = "bgp"


  values = {
    version = local.bgp_module_version

    op_vault         = local.op_vault
    op_item_proxmox  = "pve1"
    op_item_routeros = "rb5009"

    cluster_name = local.config.clusterName

    bgp_router_id = cidrhost(local.vlan_cidr, 1)

    nodes = {
      for idx, node in local.config.nodes : node.hostname => {
        ip_address = node.ipAddress
      }
    }
  }
}
