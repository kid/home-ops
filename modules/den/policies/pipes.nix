# Quirk-collection pipes.
{ den, ... }:
let
  inherit (den.lib.policy) pipe;
in
{
  # Collects the `firewall` quirk (den.quirks.firewall — rule fragments
  # emitted by network/cluster/etc. aspects, see modules/den/quirks/
  # firewall.nix) onto every RouterOS device, exposed as the `firewall` list
  # arg to any terragrunt-stacks module that names it (currently only
  # modules/routeros/firewall.nix, on rb5009).
  den.policies.routeros-device-collect-firewall = _: [
    (pipe.from "firewall" [
      # Predicate arg names double as the entity-kind filter (den's
      # findMatchingAll requires a predicate's declared entity-kind args to
      # exactly cover a candidate scope's own kind, or it's rejected) — a
      # bare `_: true` matches nothing, it names no entity kind at all. The
      # `!= null` (always true — these args are never actually null) is
      # just there so the binding isn't "unused" and treefmt's deadnix pass
      # doesn't strip the name back down to `_`, silently breaking this
      # again.
      (pipe.collectAll ({ network, ... }: network != null))
      (pipe.collectAll ({ cluster, ... }: cluster != null))
    ])
  ];

  # Collects the `k3s-nodes` quirk (emitted per-host by
  # modules/nixos/services/k3s/{k3s,agent}.nix, {hostname; address; role;
  # cluster;}) onto every RouterOS device, exposed as the `k3s-nodes` list
  # arg to modules/routeros/bgp.nix, which groups it by `cluster` into one
  # BGP stack per cluster. `host` is the entity kind — a bare `_: true`
  # predicate would match nothing, see routeros-device-collect-firewall above.
  den.policies.routeros-device-collect-k3s-nodes = _: [
    (pipe.from "k3s-nodes" [ (pipe.collectAll ({ host, ... }: host != null)) ])
  ];

  # Collects the `bgp` quirk (den.quirks.bgp — cluster-level BGP instance
  # parameters, see modules/den/quirks/bgp.nix) onto every RouterOS
  # device, exposed as the `bgp` list arg to modules/routeros/
  # ros-bgp.nix.
  den.policies.routeros-device-collect-bgp = _: [
    (pipe.from "bgp" [ (pipe.collectAll ({ cluster, ... }: cluster != null)) ])
  ];

  den.schema.routerosDevice.includes = [
    den.policies.routeros-device-collect-firewall
    den.policies.routeros-device-collect-k3s-nodes
    den.policies.routeros-device-collect-bgp
  ];

  # Collects the `miroir-nodes` quirk (emitted per-host by
  # modules/nixos/services/k3s/miroir.nix, {hostname; address; cluster;})
  # onto the cluster the host belongs to, exposed as the `miroir-nodes` list
  # arg to modules/kubernetes/miroir/default.nix's k8s-manifests
  # content. `host` is the entity kind — a bare `_: true` predicate would
  # match nothing, see routeros-device-collect-firewall above. The cluster
  # match is a filter on the collected values rather than in the predicate:
  # a host's settings.k3s.clusterName has no default, so reading it on a
  # non-k3s host throws.
  den.policies.cluster-collect-miroir-nodes =
    { cluster, ... }:
    [
      (pipe.from "miroir-nodes" [
        (pipe.collectAll ({ host, ... }: host != null))
        (pipe.filter (n: n.cluster == cluster.name))
      ])
    ];

  # Same, for the `k3s-nodes` quirk (modules/kubernetes/cilium/host-firewall.nix,
  # modules/kubernetes/victoria-metrics/default.nix).
  den.policies.cluster-collect-k3s-nodes =
    { cluster, ... }:
    [
      (pipe.from "k3s-nodes" [
        (pipe.collectAll ({ host, ... }: host != null))
        (pipe.filter (n: n.cluster == cluster.name))
      ])
    ];

  # Collects the `nfs-exports` quirk (modules/den/quirks/nfs-exports.nix,
  # emitted by cluster-scoped app aspects) onto every host, exposed as the
  # `nfs-exports` list arg to NixOS content; only node0 reads it. `cluster` is the
  # entity kind, see routeros-device-collect-firewall above.
  den.policies.host-collect-nfs-exports = _: [
    (pipe.from "nfs-exports" [ (pipe.collectAll ({ cluster, ... }: cluster != null)) ])
  ];

  # Same for the `k3s-nodes` quirk: node0 exports a cluster's writable
  # datasets (an nfs-exports fragment's `writer`) read-write only to that
  # cluster's nodes. `host` is the entity kind, as above.
  den.policies.host-collect-k3s-nodes = _: [
    (pipe.from "k3s-nodes" [ (pipe.collectAll ({ host, ... }: host != null)) ])
  ];

  den.schema.host.includes = [
    den.policies.host-collect-nfs-exports
    den.policies.host-collect-k3s-nodes
  ];

  den.schema.cluster.includes = [
    den.policies.cluster-collect-miroir-nodes
    den.policies.cluster-collect-k3s-nodes
  ];
}
