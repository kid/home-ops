# OpenEBS LocalPV-ZFS: node-local volumes as ZFS datasets under a parent
# dataset each node creates (den.aspects.k3s.zfs-localpv-node,
# modules/nixos/services/k3s/zfs-localpv.nix), with ZFS snapshots behind
# VolumeSnapshots. The standalone chart, not the openebs umbrella one.
#
# The node plugin runs `zfs` through the chart's openebs-zfspv-bin wrapper:
# `chroot /host <zfs.bin>` after trying /sbin/zfs and /usr/sbin/zfs, neither
# of which exists on NixOS. zfs.bin points it at the system profile's zfs
# (boot.supportedFilesystems puts it there), the userland built for the
# node's own ZFS kernel module.
_:
let
  # The parent dataset den.aspects.k3s.zfs-localpv-node creates on every node.
  poolname = "zroot/k8s";
in
{
  den.aspects.kubernetes.zfs-localpv.k8s-manifests =
    {
      charts,
      generators,
      cluster,
      ...
    }:
    {
      nixidy.applicationImports = [
        (generators.fromChartCRDModule {
          name = "snapshot-controller";
          chart = charts.home-operations.snapshot-controller;
          kindFilter = [ "VolumeSnapshotClass" ];
        })
      ];

      applications.zfs-localpv = {
        namespace = "zfs-localpv";

        # The node plugin runs hostNetwork: true, outside pod policies.
        resources.ciliumNetworkPolicies = with cluster.methods.netpol; {
          zfs-localpv-controller = mkPolicy { name = "openebs-zfs-controller"; } {
            egress = [ apiserverEgress ];
          };
        };

        helm.releases.zfs-localpv = {
          chart = charts.openebs.zfs-localpv;
          values = {
            zfs.bin = "/run/current-system/sw/bin/zfs";
            analytics.enabled = false;
            # den.aspects.kubernetes.snapshot-controller installs the
            # VolumeSnapshot CRDs and the one snapshot-controller.
            crds.csi.volumeSnapshots.enabled = false;
            zfsController.snapshotController.enabled = false;
          };
        };

        resources.storageClasses.zfs = {
          metadata.annotations."storageclass.kubernetes.io/is-default-class" = "true";
          provisioner = "zfs.csi.openebs.io";
          volumeBindingMode = "WaitForFirstConsumer";
          allowVolumeExpansion = true;
          reclaimPolicy = "Delete";
          parameters = {
            inherit poolname;
            fstype = "zfs";
          };
        };

        resources.volumeSnapshotClasses.zfs = {
          metadata.annotations."snapshot.storage.kubernetes.io/is-default-class" = "true";
          driver = "zfs.csi.openebs.io";
          deletionPolicy = "Delete";
        };
      };
    };
}
