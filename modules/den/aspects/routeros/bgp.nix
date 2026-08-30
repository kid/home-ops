# Shared "ros-bgp" RouterOS stack aspect — configures a RouterOS BGP instance
# on rb5009 so it peers directly with Cilium's BGP Control Plane over the
# K3s VLAN (see modules/den/aspects/kubernetes/cilium/bgp.nix for the Cilium side).
# Two decoupled producers feed this, same "many producers, one consumer"
# pattern as ros-firewall.nix:
#   - `bgp` quirk (cluster-level name/localAsn/peers/timers, emitted by
#     den.aspects.prd.bgp in modules/den/clusters/prd.nix, collected via
#     modules/den/policies/pipes.nix's routeros-device-collect-bgp)
#   - `k3s-nodes` quirk (per-host K3s-VLAN address, emitted by
#     den.aspects.k3s-server.k3s-nodes in modules/den/aspects/services/
#     k3s/k3s.nix, collected via routeros-device-collect-k3s-nodes)
# terragrunt-infra-catalog's ros-bgp module (generic RouterOS
# routeros_routing_bgp_{instance,template,connection} resources keyed by a
# `nodes` map — renamed from talos-bgp, since it's used here for k3s/Cilium
# peering, not Talos) takes ONE shared bgp_local_asn (this router's own
# ASN) / bgp_router_id (this router's own IP) pair and ONE shared
# bgp_remote_asn (Cilium's ASN) applied to every node connection — there's
# no per-peer ASN, matching Cilium's own single-bgpInstance design.
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
        stack = routerosDevice.aspect.terragruntInputs.bgp;

        # Flatten each `bgp` fragment's peers down to the ones actually
        # targeting this device — mirrors ros-firewall.nix's per-network
        # scoping. Exactly one fragment/one peer in this fleet today.
        connections = lib.concatMap (
          frag:
          map (peer: {
            inherit (frag)
              name
              localAsn
              holdTimeSeconds
              keepAliveTimeSeconds
              ;
            inherit (peer) ip asn;
          }) (lib.filter (p: p.name == routerosDevice.name) frag.peers)
        ) bgp;
        conn = lib.head connections;

        # Drop hosts with no real K3s-VLAN address (e.g. test-vm, a
        # throwaway QEMU smoke-test host — see k3s.nix's k3s-nodes quirk).
        nodes = lib.listToAttrs (
          map (n: lib.nameValuePair n.hostname { ip_address = n.address; }) (
            lib.filter (n: n.address != null) k3s-nodes
          )
        );
      in
      {
        stack = "bgp";
        moduleSource = "ros-bgp";
        moduleVersion = "2.0.0";
        inherit (stack) dependsOn;
        inputs = stack.inputs // {
          cluster_name = conn.name;
          bgp_local_asn = conn.asn;
          bgp_remote_asn = conn.localAsn;
          bgp_router_id = conn.ip;
          bgp_hold_time = formatRouterosDuration conn.holdTimeSeconds;
          bgp_keepalive_time = formatRouterosDuration conn.keepAliveTimeSeconds;
          inherit nodes;
        };
      };
  };
}
