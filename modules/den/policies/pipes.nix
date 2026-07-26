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
  den.policies.cluster-collect-k3s-nodes = _: [
    (pipe.from "k3s-nodes" [ (pipe.collectAll (_: true)) ])
  ];
}
