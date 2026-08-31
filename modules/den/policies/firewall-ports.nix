# Collects the `firewall-ports` quirk (den.quirks.firewall-ports — port
# fragments emitted by cluster-scoped Kubernetes app aspects, see
# modules/den/quirks/firewall-ports.nix) onto every cluster, exposed as the
# `firewall-ports` list arg to any k8s-manifests content function that names
# it (currently only modules/den/aspects/kubernetes/cilium/host-firewall.nix).
# Mirrors modules/den/policies/pipes.nix's routeros-device-collect-bgp
# (single collectAll stage).
#
# Host-level (NixOS daemon) contributions were dropped from this quirk: den
# does not reliably deliver a host-scope-emitted quirk to a cluster-scope
# consumer — confirmed empirically (host->cluster and host->routerosDevice
# via a *new* consumer both silently resolve empty, even reproducing the
# failure with the already-proven-working `k3s-nodes` quirk) and via den's
# own pipeline internals (mkInstantiateArgs restricts a k8s-manifests
# instantiate to its own scope subtree — ancestors + descendants only — and
# a `host` scope is neither for a `cluster` scope). Worth a precise upstream
# report to den; not something to route around here. SSH/apiserver/kubelet
# ports are declared directly in modules/den/clusters/prd.nix instead (same
# scope as this consumer, the pattern that's proven to work).
{ den, ... }:
let
  inherit (den.lib.policy) pipe;
in
{
  den.policies.cluster-collect-firewall-ports = _: [
    (pipe.from "firewall-ports" [
      # Predicate arg name doubles as the entity-kind filter — see
      # pipes.nix's own comment on this same gotcha. A bare `_: true`
      # matches nothing.
      (pipe.collectAll ({ cluster, ... }: cluster != null))
    ])
  ];

  den.schema.cluster.includes = [ den.policies.cluster-collect-firewall-ports ];
}
