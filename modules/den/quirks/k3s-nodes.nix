# Quirk metadata registration. Collected onto every RouterOS device by
# modules/den/policies/pipes.nix's routeros-device-collect-k3s-nodes,
# consumed by modules/den/aspects/routeros/bgp.nix.
{
  den.quirks.k3s-nodes.description = "k3s node info (hostname, K3s-VLAN address) for RouterOS BGP config generation";
}
