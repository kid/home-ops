# Collects the `datasets` quirk (modules/den/quirks/disko.nix) across a
# host's full aspect-includes chain and wires the merged result into
# disko-zfs, mirroring impermanence/collect.nix's `persist`/`cache`
# collection. `datasets` is a den-injected special module arg — the list of
# every included aspect's own top-level `datasets` attrset (e.g.
# modules/nixos/services/k3s/containerd.nix's
# `datasets."zroot/local/containerd" = { ... }`).
#
# disko-zfs only creates/manages the ZFS dataset and its properties — unlike
# disko, it doesn't derive NixOS `fileSystems` entries from them. So for any
# dataset that declares a `mountpoint`, this collector also emits the
# corresponding `fileSystems.<mountpoint>` entry itself.
#
# Also mirrors those entries into virtualisation.vmVariantWithDisko, for the
# same reason zfs.nix does it for /persist and /cache:
# system.build.vmWithDisko (see modules/hosts/test-vm.nix) rebuilds
# fileSystems from scratch under virtualisation.fileSystems, and only
# datasets declared through disko.devices get carried over automatically —
# confirmed by booting test-vm: without this mirror, disko-zfs still creates
# zroot/local/containerd fine, but `zfs list` shows it unmounted and
# containerd silently writes to the root fs instead.
{
  den.aspects.disk.zfs.collect.nixos =
    { datasets, lib, ... }:
    let
      merged = lib.foldl' lib.recursiveUpdate { } datasets;

      # x-systemd.after, as disko-zfs does for disko's own datasets: on the
      # switch that adds a dataset, local-fs-pre.target is long reached, and
      # only this keeps its new mount from starting before disko-zfs creates it.
      mountedFileSystems =
        merged
        |> lib.filterAttrs (_: v: v ? mountpoint)
        |> lib.mapAttrs' (
          name: v:
          lib.nameValuePair v.mountpoint {
            device = name;
            fsType = "zfs";
            options = [ "x-systemd.after=disko-zfs.service" ];
          }
        );
    in
    {
      disko.zfs.settings.datasets = lib.mapAttrs (_: v: { properties = v.properties or { }; }) merged;

      fileSystems = mountedFileSystems;

      virtualisation.vmVariantWithDisko.virtualisation.fileSystems = mountedFileSystems;
    };
}
