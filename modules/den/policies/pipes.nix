# Quirk-collection pipes. Ported from nixopslab's modules/den/policies/pipes.nix.
{ den, ... }:
let
  inherit (den.lib.policy) pipe;
in
{
  # Collects the `k3s-nodes` quirk (emitted per-host by
  # modules/den/aspects/services/k3s.nix, {hostname; localASN;}) up into
  # cluster scope, exposed as the `k3s-nodes` list arg to any k8s-manifests
  # module in that cluster (e.g. modules/kubernetes/cilium/bgp.nix, for
  # per-node CiliumBGPClusterConfig generation).
  # `host` is the entity kind — a bare `_: true` predicate matches nothing
  # (den's findMatchingAll requires the predicate to name the target entity
  # kind as a real arg), which is what this actually was until now: silently
  # dead, since nothing has consumed `k3s-nodes` yet to notice. See
  # device-collect-firewall below for how this was found.
  den.policies.cluster-collect-k3s-nodes = _: [
    (pipe.from "k3s-nodes" [ (pipe.collectAll ({ host, ... }: host != null)) ])
  ];

  # Collects the `firewall` quirk (den.quirks.firewall — rule fragments
  # emitted by network/cluster/etc. aspects, see modules/den/quirks/
  # firewall.nix) onto every device, exposed as the `firewall` list arg to
  # any terragrunt-stacks module that names it (currently only
  # modules/network/aspects/ros-firewall.nix, on rb5009).
  den.policies.device-collect-firewall = _: [
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

  den.schema.device.includes = [ den.policies.device-collect-firewall ];
}
