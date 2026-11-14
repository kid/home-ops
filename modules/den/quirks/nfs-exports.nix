# ZFS datasets node0 creates on zroot and exports over NFS to the Storage
# VLAN, contributed by cluster-scoped Kubernetes app aspects and collected onto
# every host (modules/den/policies/pipes.nix's host-collect-nfs-exports);
# only node0, the NFS server, consumes them (modules/hosts/node0.nix).
# Fragment shape: `cluster.methods.nfsExport <app> // { properties ? { }; sanoid ? { }; writer ? <cluster>; }`:
# `dataset` zroot/clusters/<cluster>/apps/<app>, mounted (inherited ZFS
# mountpoint) and exported at `path` /srv/clusters/<cluster>/apps/<app>, which
# the app's pods mount; `properties` extra ZFS properties; `sanoid`, when set,
# the dataset's `services.sanoid.datasets` entry (node0 snapshots nothing else),
# also copied to tank by syncoid; `writer`, when set, the cluster whose k3s
# nodes (the k3s-nodes quirk) get the export read-write, through their Storage
# addresses; every other client gets it read-only.
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
