# Shared "ros-bgp" RouterOS stack aspect — configures a RouterOS BGP instance
# on rb5009 so it peers directly with Cilium's BGP Control Plane over each
# cluster's VLAN (see modules/kubernetes/cilium/bgp.nix for the Cilium side).
# Two decoupled producers feed this, same "many producers, one consumer"
# pattern as ros-firewall.nix:
#   - `bgp` quirk (cluster-level name/localAsn/peers/timers/stack, emitted by
#     den.aspects.kubernetes.cilium-bgp.bgp in modules/kubernetes/cilium/
#     bgp.nix, collected via modules/den/policies/pipes.nix's
#     routeros-device-collect-bgp)
#   - `k3s-nodes` quirk (per-host address and cluster, emitted by
#     den.aspects.k3s.{server,agent}.k3s-nodes in modules/nixos/services/
#     k3s/, collected via routeros-device-collect-k3s-nodes)
# terragrunt-infra-catalog's ros-bgp module (generic RouterOS
# routeros_routing_bgp_{instance,template,connection} resources keyed by a
# `nodes` map — renamed from talos-bgp, since it's used here for k3s/Cilium
# peering, not Talos) takes ONE shared bgp_local_asn (this router's own
# ASN) / bgp_router_id (this router's own IP) pair and ONE shared
# bgp_remote_asn (Cilium's ASN) applied to every node connection, and names
# every resource after cluster_name. So each cluster peering with this
# device gets its own stack (den.clusters.<name>.bgp.routerosStack) with
# only its own nodes.
{ lib, ... }:
let
  # RouterOS echoes duration values back in its own canonical form (e.g.
  # 90 seconds reads back as "1m30s", not "90s") — the ebogdum/routeros
  # provider's plugin-framework-based consistency check treats a
  # non-canonical value we send as a post-apply drift and errors ("provider
  # produced inconsistent result"). Send the canonical form ourselves.
  formatRouterosDuration =
    totalSeconds:
    let
      w = totalSeconds / 604800;
      afterW = totalSeconds - (w * 604800);
      d = afterW / 86400;
      afterD = afterW - (d * 86400);
      h = afterD / 3600;
      afterH = afterD - (h * 3600);
      m = afterH / 60;
      s = afterH - (m * 60);
      segmentsWithoutSeconds =
        lib.optional (w > 0) "${toString w}w"
        ++ lib.optional (d > 0) "${toString d}d"
        ++ lib.optional (h > 0) "${toString h}h"
        ++ lib.optional (m > 0) "${toString m}m";
    in
    lib.concatStrings (
      segmentsWithoutSeconds ++ lib.optional (s > 0 || segmentsWithoutSeconds == [ ]) "${toString s}s"
    );
in
{
  den.aspects.routeros.bgp = {
    "terragrunt-stacks" =
      {
        routerosDevice,
        bgp ? [ ],
        k3s-nodes ? [ ],
        ...
      }:
      let
        device = routerosDevice.aspect.terragruntInputs.bgp;

        # Drop hosts with no real address (e.g. test-vm, a throwaway QEMU
        # smoke-test host — see k3s.nix's k3s-nodes quirk).
        nodesByCluster = k3s-nodes |> lib.filter (n: n.address != null) |> lib.groupBy (n: n.cluster);

        mkStack = frag: peer: {
          inherit (frag) stack;
          moduleSource = "ros-bgp";
          moduleVersion = "2.0.0";
          inherit (device) dependsOn;
          inputs = device.inputs // {
            cluster_name = frag.name;
            bgp_local_asn = peer.asn;
            bgp_remote_asn = frag.localAsn;
            bgp_router_id = peer.ip;
            bgp_hold_time = formatRouterosDuration frag.holdTimeSeconds;
            bgp_keepalive_time = formatRouterosDuration frag.keepAliveTimeSeconds;
            nodes =
              nodesByCluster.${frag.name} or [ ]
              |> map (n: lib.nameValuePair n.hostname { ip_address = n.address; })
              |> lib.listToAttrs;
          };
        };
      in
      {
        # One stack per `bgp` fragment peer targeting this device — mirrors
        # ros-firewall.nix's per-network scoping.
        stacks =
          bgp
          |> lib.concatMap (
            frag: frag.peers |> lib.filter (p: p.name == routerosDevice.name) |> map (mkStack frag)
          );
      };
  };
}
