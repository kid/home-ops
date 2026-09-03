# Cilium CNI, configured for kube-proxy replacement + native routing to
# match modules/den/aspects/services/k3s/k3s.nix's k3s flags
# (--flannel-backend=none --disable-network-policy --disable-kube-proxy).
_: {
  # cilium-agent health (9879), Hubble gRPC (4244), and cilium-envoy (9964) bind on the host itself.
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
    {
      port = 9964;
      protocol = "TCP";
      description = "cilium-envoy";
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
            egressGateway.enabled = true;

            hostFirewall.enabled = true;

            bgpControlPlane.enabled = true;

            # Ingress duty, replacing traefik. Requires gateway-api-crds.nix's
            # CRDs applied first (see bootstrap.nix's wave ordering).
            gatewayAPI.enabled = true;
            # Chart default "auto" needs a live cluster to detect; nixidy
            # renders offline, so the GatewayClass would never appear.
            gatewayAPI.gatewayClass.create = "true";

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
