# The cluster's egress IPs (den.clusters.<name>.egressGateways) that this node
# carries, added to its primary NIC's .network (modules/nixos/base/network.nix)
# next to the node's static address. /32: a second address in the VLAN's /24
# that came up before the node's own would become the subnet's primary
# address and with it the node's source address; a /32 adds no subnet route.
#
# Every node needs one per app: the app's pods leave from the node they run
# on, and on a node without one they would leave with its own IP, which the
# RouterOS rules don't admit.
{ config, den, ... }:
let
  clusters = config.den.clusters or { };
in
{
  den.aspects.k3s.egress-gateway.nixos =
    { host, lib, ... }:
    let
      inherit (host.settings.k3s) clusterName;
      cluster = clusters.${clusterName};
    in
    {
      assertions =
        cluster.egressGateways
        |> lib.mapAttrsToList (
          app: nodes: {
            assertion = nodes ? ${host.name};
            message = "den.clusters.${clusterName}.egressGateways.${app} has no address for ${host.name}";
          }
        );

      systemd.network.networks."10-${lib.toLower cluster.network}".address =
        cluster.egressGateways
        |> lib.mapAttrsToList (_: nodes: nodes.${host.name} or null)
        |> lib.filter (address: address != null)
        |> map (address: "${address}/32");
    };

  den.aspects.k3s.cilium.includes = [ den.aspects.k3s.egress-gateway ];
}
