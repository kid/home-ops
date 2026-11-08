# builtins.toJSON (valid YAML) avoids hand-indented YAML silently nesting `ingress`/`toPorts` wrong.
{ lib, ... }:
{
  den.aspects.kubernetes.cilium-host-firewall.k8s-manifests =
    {
      firewall-ports ? [ ],
      k3s-nodes ? [ ],
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
          # world: LAN clients via the kube-api LoadBalancer IP. It doesn't cover cluster
          # (nodes, pods).
          from = [
            "cluster"
            "world"
          ];
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
        ports
        |> lib.groupBy (p: p.from |> lib.sort lib.lessThan |> lib.concatStringsSep ",")
        |> lib.mapAttrsToList (
          _: group: {
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
          }
        );

      # nodeSelector, not podSelector/endpointSelector — the shape Cilium's host firewall uses.
      # It matches the host endpoint's labels, not the Node object's: Cilium's
      # default label filter drops kubernetes.io/* there (a kubernetes.io/os
      # selector matches no node) but keeps node-role.kubernetes.io/*.
      mkPolicy = name: nodeSelector: ingress: {
        apiVersion = "cilium.io/v2";
        kind = "CiliumClusterwideNetworkPolicy";
        metadata.name = name;
        spec = { inherit nodeSelector ingress; };
      };

      servers =
        k3s-nodes
        |> lib.filter (n: n.address != null && n.role == "server")
        |> map (n: n.address)
        |> lib.sort lib.lessThan;
      etcdPorts = [
        {
          ports = [
            {
              port = "2379";
              endPort = 2380;
              protocol = "TCP";
            }
          ];
        }
      ];
      # etcd between servers. A joining server has no Cilium identity until its
      # own Cilium runs, which needs its etcd member first: until then it is
      # world, matched by address. CIDR rules don't match remote-node, hence both.
      etcdIngress = lib.optionals (servers != [ ]) [
        {
          fromEntities = [ "remote-node" ];
          toPorts = etcdPorts;
        }
        {
          fromCIDR = map (a: "${a}/32") servers;
          toPorts = etcdPorts;
        }
      ];

      policies = [
        (mkPolicy "node-host-firewall" { } (mkIngress (lib.filter (p: !isControlPlane p) ports)))
        (mkPolicy "node-host-firewall-control-plane" {
          matchLabels."node-role.kubernetes.io/control-plane" = "true";
        } (mkIngress (lib.filter isControlPlane ports) ++ etcdIngress))
      ];
    in
    {
      applications.cilium.yamls =
        policies |> lib.filter (p: p.spec.ingress != [ ]) |> map builtins.toJSON;
    };
}
