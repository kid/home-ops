# Quirk metadata registration. Fragment shape: { hostname; address; role;
# cluster; } (`cluster` is the host's settings.k3s.clusterName). Collected
# onto every RouterOS device by modules/den/policies/pipes.nix's
# routeros-device-collect-k3s-nodes (consumed by modules/routeros/bgp.nix,
# grouped per cluster), and onto the host's own cluster by
# cluster-collect-k3s-nodes.
{
  den.quirks.k3s-nodes.description = "k3s node info (hostname, address, role, cluster) for RouterOS BGP and the cluster's own node lists";
}
