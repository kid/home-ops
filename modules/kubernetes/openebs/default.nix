# OpenEBS ZFS-LocalPV, using node1's existing zroot/k8s dataset as the pool.
_: {
  den.aspects.openebs.k8s-manifests =
    { charts, ... }:
    {
      applications.openebs = {
        namespace = "openebs";
        createNamespace = true;

        helm.releases.openebs = {
          chart = charts.openebs.zfs-localpv;
        };

        resources.storageClasses.openebs-zfs = {
          metadata.annotations."storageclass.kubernetes.io/is-default-class" = "true";
          provisioner = "zfs.csi.openebs.io";
          parameters.poolname = "zroot/k8s";
          volumeBindingMode = "WaitForFirstConsumer";
          allowVolumeExpansion = true;
        };
      };
    };
}
