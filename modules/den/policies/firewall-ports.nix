# Collects the `firewall-ports` quirk (den.quirks.firewall-ports — port
# fragments emitted by cluster-scoped Kubernetes app aspects, see
# modules/den/quirks/firewall-ports.nix) onto every cluster, exposed as the
# `firewall-ports` list arg to any k8s-manifests content function that names
# it (currently only modules/den/aspects/kubernetes/cilium/host-firewall.nix).
# Mirrors modules/den/policies/pipes.nix's routeros-device-collect-bgp
# (single collectAll stage).
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
