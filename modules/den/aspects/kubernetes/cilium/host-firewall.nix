# Renders one CiliumClusterwideNetworkPolicy selecting every node
# (nodeSelector, not podSelector/endpointSelector — the CCNP shape Cilium's
# host firewall uses) from every `firewall-ports` fragment collected onto
# this cluster (modules/den/policies/firewall-ports.nix) — cluster-scoped
# Kubernetes app aspects only. SSH/apiserver/kubelet are declared directly
# below instead, since den doesn't reliably deliver a host-scope-emitted
# quirk to a cluster-scope consumer (see modules/den/quirks/firewall-ports.nix).
#
# Cilium's host firewall does not auto-exempt Cilium's own control-plane
# traffic once enabled — every port here, including Cilium's own (see
# default.nix's firewall-ports fragment), is genuinely required.
#
# Built as a plain attrset and serialized with builtins.toJSON (valid YAML)
# rather than hand-templated multi-line YAML — bgp.nix already uses this
# for its `peers` list; a nested list-of-mappings structure like `ingress`
# needs it even more, since hand-indented YAML silently produces a
# structurally wrong document (toPorts ends up a sibling of ingress instead
# of nested in it) the moment indentation is off by one column.
#
# This CR is only enforced once cilium.hostFirewall.enabled is set (see
# default.nix's `devices`/`hostFirewall` values) — until then it's rendered
# and applied but inert.
{ lib, ... }:
{
  den.aspects.kubernetes.cilium-host-firewall.k8s-manifests =
    {
      firewall-ports ? [ ],
      ...
    }:
    let
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
