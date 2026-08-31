# Renders one CiliumClusterwideNetworkPolicy selecting every node
# (nodeSelector, not podSelector/endpointSelector — the CCNP shape Cilium's
# host firewall uses) from every `firewall-ports` fragment collected onto
# this cluster (modules/den/policies/firewall-ports.nix's
# cluster-collect-firewall-ports pipe) — cluster-scoped Kubernetes app
# aspects only (e.g. cilium's own hostNetwork ports); see
# modules/den/quirks/firewall-ports.nix for why NixOS host-level daemon
# ports (SSH, apiserver, kubelet) aren't collected this way and are instead
# declared directly below in this same file.
#
# `firewall-ports` is consumed here as a plain k8s-manifests function arg —
# NOT threaded through an intermediate den.policies.* function — because
# den only reliably resolves quirk args inside class-content functions
# (confirmed against den's own test suite, templates/ci/modules/
# public-api/pipes.nix's test-pipe-discriminator).
#
# Raw YAML via applications.cilium.yamls, matching this repo's existing
# convention for every other Cilium CR (bgp.nix, egress-gateway.nix) — no
# typed nixidy CRD generator exists for any Cilium-native CRD here. Built as
# a plain attrset and serialized with builtins.toJSON (valid YAML) rather
# than hand-templated multi-line YAML — bgp.nix already uses this for its
# `peers` list; a nested list-of-mappings structure like `ingress` needs it
# even more, since hand-indented YAML silently produces a structurally
# wrong document (toPorts ends up a sibling of ingress instead of nested in
# it) the moment indentation is off by one column.
#
# Cilium's host firewall does NOT auto-exempt Cilium's own control-plane
# traffic once enabled (confirmed against docs.cilium.io/.../host-firewall/
# and .../security/policy/host/) — every port here is genuinely required,
# not defensive over-caution. See modules/den/aspects/kubernetes/cilium/
# default.nix's own firewall-ports fragment for Cilium's own ports.
#
# This CR is only enforced once cilium.hostFirewall.enabled is set (see
# default.nix's `devices`/`hostFirewall` values) — until then it's rendered
# and applied but inert, which is deliberate: it lets the whole pipeline
# (this file, write-manifests, the port inventory) be validated with zero
# enforcement risk before host-firewall enforcement is ever turned on.
{ lib, ... }:
{
  den.aspects.kubernetes.cilium-host-firewall.k8s-manifests =
    {
      firewall-ports ? [ ],
      ...
    }:
    let
      # SSH/apiserver/kubelet: same-scope declaration (see this file's top
      # comment) — not co-located with ssh.nix/k3s.nix, but same mechanism
      # everything else here uses.
      hostPorts = [
        {
          port = 22;
          protocol = "TCP";
          description = "SSH (node1)";
          from = [ "world" ];
        }
        {
          port = 6443;
          protocol = "TCP";
          description = "kube-apiserver";
          from = [ "cluster" ];
        }
        {
          port = 10250;
          protocol = "TCP";
          description = "kubelet";
          from = [ "cluster" ];
        }
      ];

      ports = firewall-ports ++ hostPorts;
      byScope = lib.groupBy (p: lib.concatStringsSep "," (lib.sort lib.lessThan p.from)) ports;

      ingress = lib.mapAttrsToList (_: group: {
        fromEntities = (builtins.head group).from;
        toPorts = [
          {
            ports = map (p: {
              port = toString p.port;
              inherit (p) protocol;
            }) group;
          }
        ];
      }) byScope;

      policy = {
        apiVersion = "cilium.io/v2";
        kind = "CiliumClusterwideNetworkPolicy";
        metadata.name = "node-host-firewall";
        spec = {
          nodeSelector.matchLabels."kubernetes.io/os" = "linux";
          inherit ingress;
        };
      };
    in
    {
      applications.cilium.yamls = lib.optionals (ports != [ ]) [ (builtins.toJSON policy) ];
    };
}
