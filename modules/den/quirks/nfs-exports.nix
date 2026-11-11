# ZFS datasets node0 creates on zroot and exports over NFS to the Storage
# VLAN, contributed by cluster-scoped Kubernetes app aspects and collected onto
# every host (modules/den/policies/pipes.nix's host-collect-nfs-exports);
# only node0, the NFS server, consumes them (modules/hosts/node0.nix).
# Fragment shape: { dataset; path; properties ? { }; } — `path` is both the
# mountpoint and the export, `properties` extra ZFS properties.
{
  den.quirks.nfs-exports.description = "zroot datasets node0 creates and exports over NFS, contributed by cluster-scoped Kubernetes app aspects";
}
