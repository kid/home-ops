# builtins.toJSON (valid YAML) avoids hand-indented YAML silently nesting `ingress`/`toPorts` wrong.
{ lib, ... }:
{
  den.aspects.kubernetes.cilium-host-firewall.k8s-manifests =
    {
      firewall-ports ? [ ],
      ...
    }:
    let
      # Declared here, not ssh.nix/k3s.nix: a host-scope quirk can't reach this cluster-scope consumer.
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
          # nodeSelector, not podSelector/endpointSelector — the shape Cilium's host firewall uses.
          nodeSelector.matchLabels."kubernetes.io/os" = "linux";
          inherit ingress;
        };
      };
    in
    {
      applications.cilium.yamls = lib.optionals (ports != [ ]) [ (builtins.toJSON policy) ];
    };
}
