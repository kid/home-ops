# The cluster's egress IPs (den.clusters.<name>.egressGateways) that this node
# carries, added to its primary NIC's .network (modules/nixos/base/network.nix)
# next to the DHCP lease. /32: a second address in the VLAN's /24 that came
# up before the lease would become the subnet's primary address and with it
# the node's source address; a /32 adds no subnet route.
{ config, den, ... }:
let
  clusters = config.den.clusters or { };
in
{
  den.aspects.k3s-egress-gateway.nixos =
    { host, lib, ... }:
    let
      cluster = clusters.${host.k3s.clusterName or "prd"};
      addresses =
        cluster.egressGateways
        |> lib.filterAttrs (_: gateway: gateway.node == host.name)
        |> lib.mapAttrsToList (_: gateway: "${gateway.address}/32");
    in
    {
      systemd.network.networks."10-${lib.toLower cluster.network}".address = addresses;
    };

  den.aspects.k3s-cilium.includes = [ den.aspects.k3s-egress-gateway ];
}
