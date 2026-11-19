# ZFS datasets the NFS server (k3s-prd-0) creates on zroot and exports over
# NFS to the Storage VLAN, contributed by cluster-scoped Kubernetes app
# aspects and collected onto every host (modules/den/policies/pipes.nix's
# host-collect-nfs-exports); only k3s-prd-0 consumes them
# (modules/hosts/k3s-prd-0.nix).
# Fragment shape: `cluster.methods.nfsExport <app> // { properties ? { }; sanoid ? { }; writer ? <cluster>; }`:
# `dataset` zroot/clusters/<cluster>/apps/<app>, mounted (inherited ZFS
# mountpoint) and exported at `path` /srv/clusters/<cluster>/apps/<app>, which
# the app's pods mount (from the host, or over NFS from
# `cluster.methods.nfsServer` for kopiur's local repository); `properties`
# extra ZFS properties; `sanoid`, when set, the dataset's
# `services.sanoid.datasets` entry (k3s-prd-0 snapshots nothing else),
# also copied to tank by syncoid; `writer`, when set, the cluster whose k3s
# nodes (the k3s-nodes quirk) get the export read-write, through their Storage
# addresses; every other client gets it read-only.
{ config, lib, ... }:
let
  nfsExport = cluster: app: {
    dataset = "zroot/clusters/${cluster}/apps/${app}";
    path = "/srv/clusters/${cluster}/apps/${app}";
  };
  # The clients reach the server on the Storage VLAN, not through the router.
  nfsServer =
    config.den.devices.k3s-prd-0.interfaces
    |> lib.findFirst (i: i.network == "Storage") (throw "k3s-prd-0 has no Storage interface")
    |> (i: i.address);
in
{
  den.quirks.nfs-exports.description = "zroot datasets the NFS server (k3s-prd-0) creates and exports over NFS, contributed by cluster-scoped Kubernetes app aspects";

  den.clusterMethods.nfsExport = cluster: nfsExport cluster.name;
  den.clusterMethods.nfsServer = _: nfsServer;
}
