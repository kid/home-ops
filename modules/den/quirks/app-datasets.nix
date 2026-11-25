# ZFS datasets k3s-prd-0 creates on zroot (its NVMe pool, not tank, whose
# disks spin down) for cluster-scoped Kubernetes app aspects, collected onto
# every host (modules/den/policies/pipes.nix's host-collect-app-datasets);
# only k3s-prd-0 consumes them (modules/hosts/k3s-prd-0.nix).
# Fragment shape: `cluster.methods.appDataset <app> // { properties ? { }; sanoid ? { }; nfs ? false; writer ? <cluster>; }`:
# `dataset` zroot/clusters/<cluster>/apps/<app>, mounted (inherited ZFS
# mountpoint) at `path` /srv/clusters/<cluster>/apps/<app>, which the app's
# pods mount from the host; `properties` extra ZFS properties; `sanoid`, when
# set, the dataset's `services.sanoid.datasets` entry (k3s-prd-0 snapshots
# nothing else), also copied to tank by syncoid; `nfs`, when true, also
# exports `path` over NFS on the Storage VLAN, from `cluster.methods.nfsServer`
# (kopiur's local repository); `writer`, on an NFS export, the cluster whose
# k3s nodes (the k3s-nodes quirk) get it read-write, through their Storage
# addresses; every other client gets it read-only.
{ config, lib, ... }:
let
  appDataset = cluster: app: {
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
  den.quirks.app-datasets.description = "zroot datasets k3s-prd-0 creates for cluster-scoped Kubernetes app aspects, optionally exported over NFS";

  den.clusterMethods.appDataset = cluster: appDataset cluster.name;
  den.clusterMethods.nfsServer = _: nfsServer;
}
