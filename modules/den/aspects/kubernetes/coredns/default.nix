# CoreDNS, replacing the one k3s would otherwise ship
# (modules/den/aspects/services/k3s/k3s.nix passes --disable=coredns). Pins
# service.clusterIP to cluster.networks.services.assignments.coredns so it
# matches the fixed address k3s's own --service-cidr flag expects kubelets
# to find DNS at.
_: {
  den.aspects.kubernetes.coredns.k8s-manifests =
    { charts, cluster, ... }:
    {
      applications.coredns = {
        namespace = "kube-system";
        syncPolicy.syncOptions.serverSideApply = true;

        resources.ciliumNetworkPolicies = with cluster.methods.netpol; {
          coredns = mkPolicy { k8s-app = "coredns"; } {
            ingress = [
              {
                fromEntities = [ "cluster" ];
                toPorts = tcpUdp [ 53 ];
              }
              (scrapeIngress [ 9153 ])
            ];
            egress = [
              apiserverEgress
              {
                toEntities = [ "world" ];
                toPorts = tcpUdp [ 53 ];
              }
            ];
          };
        };

        helm.releases.coredns = {
          chart = charts.coredns.coredns;
          values = {
            service.clusterIP = cluster.networks.services.assignments.coredns;
            replicaCount = 1;
            # limits.cpu = null drops the chart's default CPU limit.
            resources = {
              requests = {
                cpu = "10m";
                memory = "64Mi";
              };
              limits = {
                cpu = null;
                memory = "128Mi";
              };
            };
            prometheus = {
              service.enabled = true;
              monitor.enabled = true;
            };
          };
        };
      };
    };
}
