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
