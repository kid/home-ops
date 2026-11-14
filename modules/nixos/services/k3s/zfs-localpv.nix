# Node side of zfs-localpv (modules/kubernetes/zfs-localpv/default.nix): the
# parent dataset its StorageClass's `poolname` names. Only on a
# den.aspects.disk.zfs host, which applies the `datasets` quirk.
#
# Outside zroot/local/root, so the volumes survive the rollback on boot.
# canmount=off: the driver creates each volume as a child dataset with
# mountpoint=legacy and mounts it itself.
_: {
  den.aspects.k3s.zfs-localpv-node = {
    datasets."zroot/k8s".properties = {
      canmount = "off";
      mountpoint = "none";
    };

    # The volumes, and the clones restored from their snapshots, are the
    # driver's: disko-zfs would list each one as a dataset to destroy.
    nixos.disko.zfs.settings.ignoredDatasets = [ "zroot/k8s/*" ];
  };
}
