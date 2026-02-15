include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

include "provider_proxmox" {
  path = "${get_repo_root()}/tf-catalog/modules/_shared/provider-proxmox.hcl"
}

include "provider_routeros" {
  path = "${get_repo_root()}/tf-catalog/modules/_shared/provider-routeros.hcl"
}

terraform {
  source                   = "${get_repo_root()}/tf-catalog/modules//proxmox-talos-cluster"
  copy_terraform_lock_file = false
}

locals {
  vlans = include.root.locals.env_config.locals.vlans
}

inputs = merge(
  include.root.locals.proxmox_inputs,
  {
    routeros_endpoint     = "https://192.168.89.2"
    routeros_secrets_path = "${get_repo_root()}/secrets/dev/routeros.sops.yaml"

    cluster_name = "lab"

    dhcp_server = local.vlans.Talos.name
    vlan_id     = local.vlans.Talos.vlan_id

    nodes = {
      talos-lab-cp-0 = {
        ip_address = cidrhost(local.vlans.Talos.cidr, 11)
        cpu_cores = 4
      }
    }

    # BGP configuration for Cilium LoadBalancer services
    bgp_enabled    = true
    bgp_local_asn  = 64512                               # RouterOS ASN
    bgp_remote_asn = 64513                               # Cilium ASN
    bgp_router_id  = cidrhost(local.vlans.Talos.cidr, 1) # Router's IP on Talos VLAN

    dhcp_server = local.vlans.Talos.name
    dhcp_dns_zone = local.vlans.Talos.domain
  },
)
