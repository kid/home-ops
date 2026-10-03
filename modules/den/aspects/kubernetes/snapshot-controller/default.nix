# Installs the snapshot.storage.k8s.io CRDs and the snapshot-controller that
# k3s doesn't ship. kopiur's default copyMethod: Snapshot needs both, plus a
# VolumeSnapshotClass (miroir/default.nix, next to its StorageClass).
_: {
  den.aspects.kubernetes.snapshot-controller.k8s-manifests =
    { charts, cluster, ... }:
    {
      applications.snapshot-controller = {
        namespace = "snapshot-controller";
        annotations."argocd.argoproj.io/sync-wave" = "-3";

        resources.ciliumNetworkPolicies = with cluster.methods.netpol; {
          snapshot-controller = mkPolicy { "app.kubernetes.io/name" = "snapshot-controller"; } {
            ingress = [ (scrapeIngress [ 8080 ]) ];
            egress = [ apiserverEgress ];
          };
        };

        helm.releases.snapshot-controller = {
          chart = charts.home-operations.snapshot-controller;
          values = {
            monitoring.serviceMonitor.enabled = true;
            resources = {
              requests = {
                cpu = "10m";
                memory = "64Mi";
              };
              limits.memory = "128Mi";
            };
          };
        };
      };
    };
}
