# RouterOS BGP configuration for Cilium LoadBalancer service exposure
#
# This creates BGP peering between RouterOS and Talos nodes running Cilium.
# Cilium will advertise LoadBalancer service IPs via BGP, and RouterOS will
# learn these routes dynamically.

# BGP instance for the cluster
resource "routeros_routing_bgp_instance" "talos" {
  count = var.bgp_enabled ? 1 : 0

  name      = "${var.cluster_name}-bgp"
  as        = var.bgp_local_asn
  router_id = var.bgp_router_id
  vrf       = "main"
}

# BGP template for Talos node peers
resource "routeros_routing_bgp_template" "talos" {
  count = var.bgp_enabled ? 1 : 0

  name          = "${var.cluster_name}-peers"
  as            = var.bgp_local_asn
  routing_table = "main"

  # Accept all routes from Cilium (LoadBalancer IPs)
  hold_time      = "1m30s"
  keepalive_time = "30s"
}

# BGP connections to each Talos node
resource "routeros_routing_bgp_connection" "talos" {
  for_each = var.bgp_enabled ? local.nodes : {}

  name      = each.value.vm_name
  as        = var.bgp_local_asn
  instance  = routeros_routing_bgp_instance.talos[0].name
  templates = [routeros_routing_bgp_template.talos[0].name]

  # Connection settings
  connect = true
  listen  = true

  # Address family - IPv4 unicast
  address_families = "ip"

  # Routing table
  routing_table = "main"

  # Local configuration
  local {
    role = "ebgp"
  }

  # Remote peer (Talos node running Cilium)
  remote {
    address = each.value.ip_address
    as      = var.bgp_remote_asn
  }
}
