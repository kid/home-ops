# Cilium CNI, configured for kube-proxy replacement + native routing to
# match modules/den/aspects/services/k3s/k3s.nix's k3s flags
# (--flannel-backend=none --disable-network-policy --disable-kube-proxy).
_: {
  # cilium-agent health (9879) and Hubble gRPC (4244) bind on the host itself.
  den.aspects.kubernetes.cilium.firewall-ports = _: [
    {
      port = 9879;
      protocol = "TCP";
      description = "cilium-agent health";
      from = [
        "cluster"
        "remote-node"
      ];
    }
    {
      port = 4244;
      protocol = "TCP";
      description = "Hubble gRPC";
      from = [
        "cluster"
        "remote-node"
      ];
    }
  ];

  den.aspects.kubernetes.cilium.k8s-manifests =
    { charts, cluster, ... }:
    {
      applications.cilium = {
        namespace = "kube-system";
        syncPolicy.syncOptions.serverSideApply = true;

        helm.releases.cilium = {
          chart = charts.cilium.cilium;
          values = {
            kubeProxyReplacement = true;
            k8sServiceHost = "127.0.0.1";
            k8sServicePort = 6443;

            routingMode = "native";
            autoDirectNodeRoutes = true;
            ipv4NativeRoutingCIDR = cluster.networks.pods.cidr;

            ipam = {
              mode = "cluster-pool";
              operator.clusterPoolIPv4PodCIDRList = [ cluster.networks.pods.cidr ];
            };

            bpf.masquerade = true;

            hostFirewall.enabled = true;

            bgpControlPlane.enabled = true;

            # Gateway API is served by Envoy Gateway instead (see
            # envoy-gateway/default.nix), not Cilium's own controller.
            # envoy.enabled powers Cilium's embedded Envoy proxy, used only
            # for Ingress, Gateway API, L7 network policies, and L7
            # protocol visibility — none of which this cluster uses now.
            envoy.enabled = false;

            operator.replicas = 1;

            hubble.tls.auto = {
              method = "certmanager";
              certManagerIssuerRef = {
                group = "cert-manager.io";
                kind = "ClusterIssuer";
                name = "hubble-ca-issuer";
              };
            };
          };
        };
      };
    };
}
