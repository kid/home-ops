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
  # modules/den/aspects/routeros/firewall.nix, on rb5009).
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
  # modules/den/aspects/services/k3s/k3s.nix, {hostname; address;}) onto
  # every RouterOS device, exposed as the `k3s-nodes` list arg to
  # modules/den/aspects/routeros/bgp.nix (to build its per-node BGP
  # connections). `host` is the entity kind — a bare `_: true` predicate
  # would match nothing, see routeros-device-collect-firewall above.
  den.policies.routeros-device-collect-k3s-nodes = _: [
    (pipe.from "k3s-nodes" [ (pipe.collectAll ({ host, ... }: host != null)) ])
  ];

  # Collects the `bgp` quirk (den.quirks.bgp — cluster-level BGP instance
  # parameters, see modules/den/quirks/bgp.nix) onto every RouterOS
  # device, exposed as the `bgp` list arg to modules/den/aspects/routeros/
  # ros-bgp.nix.
  den.policies.routeros-device-collect-bgp = _: [
    (pipe.from "bgp" [ (pipe.collectAll ({ cluster, ... }: cluster != null)) ])
  ];

  den.schema.routerosDevice.includes = [
    den.policies.routeros-device-collect-firewall
    den.policies.routeros-device-collect-k3s-nodes
    den.policies.routeros-device-collect-bgp
  ];
}
