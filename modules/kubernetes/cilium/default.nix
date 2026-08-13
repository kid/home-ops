# Cilium CNI, configured for kube-proxy replacement + native routing to
# match modules/den/aspects/services/k3s/k3s.nix's k3s flags
# (--flannel-backend=none --disable-network-policy --disable-kube-proxy).
_: {
  den.aspects.cilium.k8s-manifests =
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

            bgpControlPlane.enabled = true;

            # Ingress duty, replacing traefik. Requires gateway-api-crds.nix's
            # CRDs applied first (see bootstrap.nix's wave ordering).
            gatewayAPI.enabled = true;

            operator.replicas = 1;

            # Hubble's server cert issued by cert-manager (modules/kubernetes/
            # cert-manager/default.nix's hubble-ca-issuer ClusterIssuer)
            # instead of Helm's own genSignedCert, which re-randomizes
            # cilium-ca and hubble-server-certs on every render.
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
