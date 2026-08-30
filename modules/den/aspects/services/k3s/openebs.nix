# Reserves the zroot/openebs ZFS dataset OpenEBS's ZFS-LocalPV CSI driver
# uses as its pool (modules/den/aspects/kubernetes/openebs/default.nix's poolname) —
# the driver only zfs-creates child datasets per PV under this parent,
# never the parent itself, so it must already exist before any PV can be
# provisioned.
{
  den.aspects.k3s-openebs.datasets."zroot/openebs".properties.mountpoint = "none";
}
