# CiliumEgressGatewayPolicy is a native Cilium CRD, installed by the
# cilium-operator at runtime rather than bundled in the chart's own crds/
# (Cilium ships none) — same reason bgp.nix uses raw YAML instead of
# generators.fromChartCRDModule.
_: {
  den.aspects.cilium-egress-gateway.k8s-manifests = _: {
    applications.cilium.yamls = [
      ''
        apiVersion: cilium.io/v2
        kind: CiliumEgressGatewayPolicy
        metadata:
          name: egress-gateway
        spec:
          selectors:
            - podSelector: {}
          destinationCIDRs:
            - "0.0.0.0/0"
          egressGateway:
            nodeSelector:
              matchLabels:
                kidibox.net/egress-gateway: "true"
            interface: k3s
      ''
    ];
  };
}
