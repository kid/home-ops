# Node side of miroir (modules/kubernetes/miroir/default.nix):
# an LVM-thin pool in the node's existing `vg-miroir` VG (den.aspects.incus-vm),
# replicated between nodes with DRBD.
#
# DRBD9 (>= 9.3.1) is needed on every node before miroir can replicate. The
# default kernel's drbd build can be marked broken in nixpkgs (driver.nix,
# e.g. for 6.18), so this picks the newest kernel where it is not.
# Deliberately not `lib.mkDefault`: nothing else sets boot.kernelPackages on
# a k3s node (only node1, through srvos's latest-zfs-kernel mixin).
{
  den.aspects.k3s-miroir-node = {
    miroir-nodes =
      { host, ... }:
      {
        hostname = host.name;
      };

    nixos =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        compatibleKernelPackages = lib.filterAttrs (
          name: kernelPackages:
          (builtins.match "linux_[0-9]+_[0-9]+" name) != null
          && (builtins.tryEval kernelPackages).success
          && !kernelPackages.drbd.meta.broken
        ) pkgs.linuxKernel.packages;
        latestKernelPackages =
          compatibleKernelPackages
          |> builtins.attrValues
          |> lib.sort (a: b: lib.versionOlder a.kernel.version b.kernel.version)
          |> lib.last;
      in
      {
        # Note this might jump back and forth as kernels are added or removed.
        boot.kernelPackages = latestKernelPackages;
        # Load at boot whatever miroir-agent needs: extraModulePackages turns
        # kernel-modules into a tree of /nix/store symlinks, which the agent's
        # own modprobe can't follow (only /lib/modules is mounted into it).
        # dm_snapshot backs lvcreate --snapshot (VolumeSnapshots).
        boot.kernelModules = [
          "dm_snapshot"
          "dm_thin_pool"
          "drbd"
        ];
        boot.extraModulePackages = [ config.boot.kernelPackages.drbd ];

        # miroir-agent bind-mounts the host's /lib/modules for its own
        # modprobe — NixOS leaves that path empty, so without this it fails
        # with "Module dm-thin-pool not found in directory /lib/modules/...".
        systemd.tmpfiles.rules = [
          "L+ /lib/modules - - - - /run/current-system/kernel-modules/lib/modules"
        ];
      };
  };
}
