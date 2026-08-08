# Cilium CNI, configured for kube-proxy replacement + native routing to
# match modules/den/aspects/services/k3s/k3s.nix's k3s flags
# (--flannel-backend=none --disable-network-policy --disable-kube-proxy).
# Adapted from nixopslab's modules/kubernetes/cilium/default.nix — reads
# cluster.networks.pods.cidr directly into Helm values, the clearest example
# of cluster-entity data flowing straight into a rendered manifest.
#
# NB: reconstructed from a research summary rather than a byte-for-byte
# port (unlike the other aspects in this pass) — cross-check the exact Helm
# values against a real deployment before relying on this beyond Phase 4's
# "does it evaluate" verification.
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

            operator.replicas = 1;
          };
        };
      };
    };
}
