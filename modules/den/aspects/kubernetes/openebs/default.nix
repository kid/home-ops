# OpenEBS ZFS-LocalPV, using node1's zroot/openebs dataset as the pool. The
# driver only zfs-creates child datasets per PV under this parent — it
# never creates the parent itself, which is why the dataset is requested
# separately, via modules/den/aspects/services/k3s/openebs.nix's `datasets`
# quirk (den.aspects.k3s-openebs, included on node1).
_: {
  den.aspects.kubernetes.openebs.k8s-manifests =
    { charts, ... }:
    {
      applications.openebs = {
        namespace = "openebs";
        createNamespace = true;

        # Pins the chart's own bundled CSI sidecars forward to their latest
        # same-major releases — the chart (2.10.1) hasn't moved its own
        # pins in over a year. Stops at the sidecars' latest major
        # (csi-resizer v2, csi-provisioner v6): openebs hasn't adopted
        # either upstream, so there's no real-world validation against
        # zfs-driver, and both promote VolumeAttributesClass to
        # default-on GA — deliberately deferred, not overlooked.
        helm.releases.openebs = {
          chart = charts.openebs.zfs-localpv;
          values = {
            analytics.enabled = false;

            # renovate: datasource=docker depName=registry.k8s.io/sig-storage/csi-node-driver-registrar
            zfsNode.driverRegistrar.image.tag = "v2.17.0";
            zfsController = {
              # renovate: datasource=docker depName=registry.k8s.io/sig-storage/csi-resizer
              resizer.image.tag = "v1.14.0";
              # renovate: datasource=docker depName=registry.k8s.io/sig-storage/csi-provisioner
              provisioner.image.tag = "v5.3.0";
              # renovate: datasource=docker depName=registry.k8s.io/sig-storage/csi-snapshotter
              snapshotter.image.tag = "v8.6.0";
              # renovate: datasource=docker depName=registry.k8s.io/sig-storage/snapshot-controller
              snapshotController.image.tag = "v8.6.0";
            };
          };
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
