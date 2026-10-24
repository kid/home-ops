# builtins.toJSON (valid YAML) avoids hand-indented YAML silently nesting `ingress`/`toPorts` wrong.
{ config, lib, ... }:
{
  den.aspects.kubernetes.cilium-host-firewall.k8s-manifests =
    {
      cluster,
      firewall-ports ? [ ],
      ...
    }:
    let
      # Declared here, not ssh.nix/k3s.nix: a host-scope quirk can't reach this cluster-scope consumer.
      hostPorts = [
        {
          port = 22;
          protocol = "TCP";
          description = "SSH";
          from = [ "world" ];
        }
        {
          port = 6443;
          protocol = "TCP";
          description = "kube-apiserver";
          from = [ "cluster" ];
          controlPlane = true;
        }
        {
          port = 10250;
          protocol = "TCP";
          description = "kubelet";
          from = [ "cluster" ];
        }
      ];

      ports = firewall-ports ++ hostPorts;
      # A port with `controlPlane = true` is only opened on control-plane nodes.
      isControlPlane = p: p.controlPlane or false;

      mkIngress =
        ports:
        lib.mapAttrsToList (_: group: {
          fromEntities = (builtins.head group).from;
          toPorts = [
            {
              ports = map (
                p:
                {
                  port = toString p.port;
                  inherit (p) protocol;
                }
                // lib.optionalAttrs (p ? endPort) { inherit (p) endPort; }
              ) group;
            }
          ];
        }) (lib.groupBy (p: lib.concatStringsSep "," (lib.sort lib.lessThan p.from)) ports);

      # nodeSelector, not podSelector/endpointSelector — the shape Cilium's host firewall uses.
      # It matches the host endpoint's labels, not the Node object's: Cilium's
      # default label filter drops kubernetes.io/* there (a kubernetes.io/os
      # selector matches no node) but keeps node-role.kubernetes.io/*.
      mkPolicy = name: nodeSelector: ports: extraIngress: {
        apiVersion = "cilium.io/v2";
        kind = "CiliumClusterwideNetworkPolicy";
        metadata.name = name;
        spec = {
          inherit nodeSelector;
          ingress = mkIngress ports ++ extraIngress;
        };
      };

      # A node joins over the API port while Cilium still counts it as
      # `world`: it is only `cluster` once registered. The whole node VLAN,
      # so a new node needs no policy change first.
      nodeJoinIngress = [
        {
          fromCIDR = [ config.den.environments.${cluster.environment}.networks.${cluster.network}.cidr ];
          toPorts = [
            {
              ports = [
                {
                  port = "6443";
                  protocol = "TCP";
                }
              ];
            }
          ];
        }
      ];

      policies = [
        (mkPolicy "node-host-firewall" { } (lib.filter (p: !isControlPlane p) ports) [ ])
        (mkPolicy "node-host-firewall-control-plane" {
          matchLabels."node-role.kubernetes.io/control-plane" = "true";
        } (lib.filter isControlPlane ports) nodeJoinIngress)
      ];
    in
    {
      applications.cilium.yamls = map builtins.toJSON (lib.filter (p: p.spec.ingress != [ ]) policies);
    };
}
