# Same reason as egress-gateway.nix: CiliumClusterwideNetworkPolicy is a
# native Cilium CRD, not bundled in the chart's own crds/, so raw YAML
# instead of generators.fromChartCRDModule.
{ config, ... }:
let
  serversCidr = config.den.environments.prd.networks.Servers.cidr;
in
{
  den.aspects.cilium-host-firewall.k8s-manifests = _: {
    applications.cilium.yamls = [
      ''
        apiVersion: cilium.io/v2
        kind: CiliumClusterwideNetworkPolicy
        metadata:
          name: host-ssh-servers-only
        spec:
          nodeSelector:
            matchLabels:
              kidibox.net/ssh-servers-only: "true"
          ingress:
            - fromEntities:
                - cluster
            - fromCIDR:
                - "${serversCidr}"
              toPorts:
                - ports:
                    - port: "22"
                      protocol: TCP
      ''
    ];
  };
}
