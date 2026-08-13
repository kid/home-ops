# OpenEBS ZFS-LocalPV, using node1's zroot/openebs dataset as the pool. The
# driver only zfs-creates child datasets per PV under this parent — it
# never creates the parent itself, which is why the dataset is requested
# separately, via modules/den/aspects/services/k3s/openebs.nix's `datasets`
# quirk (den.aspects.k3s-openebs, included on node1).
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
          parameters.poolname = "zroot/openebs";
          volumeBindingMode = "WaitForFirstConsumer";
          allowVolumeExpansion = true;
        };
      };
    };
}
