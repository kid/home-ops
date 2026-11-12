# ZFS datasets node0 creates on zroot and exports over NFS to the Storage
# VLAN, contributed by cluster-scoped Kubernetes app aspects and collected onto
# every host (modules/den/policies/pipes.nix's host-collect-nfs-exports);
# only node0, the NFS server, consumes them (modules/hosts/node0.nix).
# Fragment shape: `cluster.methods.nfsExport <app> // { properties ? { }; sanoid ? { }; }`:
# `dataset` zroot/clusters/<cluster>/apps/<app>, mounted (inherited ZFS
# mountpoint) and exported at `path` /srv/clusters/<cluster>/apps/<app>, which
# the app's pods mount; `properties` extra ZFS properties; `sanoid`, when set,
# the dataset's `services.sanoid.datasets` entry (node0 snapshots nothing else).
let
  nfsExport = cluster: app: {
    dataset = "zroot/clusters/${cluster}/apps/${app}";
    path = "/srv/clusters/${cluster}/apps/${app}";
  };
in
{
  den.quirks.nfs-exports.description = "zroot datasets node0 creates and exports over NFS, contributed by cluster-scoped Kubernetes app aspects";

  den.clusterMethods.nfsExport = cluster: nfsExport cluster.name;
}
