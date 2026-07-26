# CoreDNS, replacing the one k3s would otherwise ship
# (modules/den/aspects/services/k3s.nix passes --disable=coredns). Adapted
# from nixopslab's modules/kubernetes/coredns/default.nix — pins
# service.clusterIP to cluster.networks.services.assignments.coredns so it
# matches the fixed address k3s's own --service-cidr flag expects kubelets
# to find DNS at.
#
# NB: reconstructed from a research summary rather than a byte-for-byte
# port — cross-check against a real deployment before relying on this
# beyond Phase 4's "does it evaluate" verification.
_: {
  den.aspects.coredns.k8s-manifests =
    { charts, cluster, ... }:
    {
      applications.coredns = {
        namespace = "kube-system";
        syncPolicy.syncOptions.serverSideApply = true;

        helm.releases.coredns = {
          chart = charts.coredns.coredns;
          values = {
            service.clusterIP = cluster.networks.services.assignments.coredns;
            replicaCount = 1;
          };
        };
      };
    };
}
