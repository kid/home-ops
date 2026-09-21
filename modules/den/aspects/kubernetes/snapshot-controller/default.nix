# Installs the snapshot.storage.k8s.io CRDs and the snapshot-controller that
# k3s doesn't ship. kopiur's default copyMethod: Snapshot needs both, plus a
# default VolumeSnapshotClass for miroir.
_: {
  den.aspects.kubernetes.snapshot-controller.k8s-manifests =
    { charts, ... }:
    {
      applications.snapshot-controller = {
        namespace = "snapshot-controller";
        createNamespace = true;
        annotations."argocd.argoproj.io/sync-wave" = "-3";

        helm.releases.snapshot-controller = {
          chart = charts.piraeusdatastore.snapshot-controller;
          values.volumeSnapshotClasses = [
            {
              name = "miroir";
              driver = "miroir.home-operations.com";
              deletionPolicy = "Delete";
              annotations."snapshot.storage.kubernetes.io/is-default-class" = "true";
            }
          ];
        };
      };
    };
}
