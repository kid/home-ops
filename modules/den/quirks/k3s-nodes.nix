# Quirk metadata registration. Fragment shape: { hostname; address; role;
# cluster; } (`cluster` is the host's settings.k3s.clusterName). Collected
# onto the host's own cluster by modules/den/policies/pipes.nix's
# cluster-collect-k3s-nodes (read by e.g. modules/aspects/kubernetes/cilium/
# bgp.nix, for the router's per-node BGP connections).
{
  den.quirks.k3s-nodes.description = "k3s node info (hostname, address, role, cluster) for RouterOS BGP and the cluster's own node lists";
}
