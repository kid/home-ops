# CoreDNS, replacing the one k3s would otherwise ship
# (modules/den/aspects/services/k3s/k3s.nix passes --disable=coredns). Pins
# service.clusterIP to cluster.networks.services.assignments.coredns so it
# matches the fixed address k3s's own --service-cidr flag expects kubelets
# to find DNS at.
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
