# Reserves the zroot/miroir ZFS dataset miroir's ZFS backend uses as its
# pool (modules/kubernetes/miroir/default.nix's MiroirNode zfs.dataset) —
# the driver only zfs-creates child datasets per PV under this parent, it
# never creates the parent itself, so it must already exist before any PV
# can be provisioned.
#
# DRBD9 (>= 9.3.1, required even for miroir's local-only, single-replica
# use today — it's needed before any node can replicate, and loading it
# ahead of a 2nd node joining is harmless) is loaded here. The default
# kernel (config.boot.kernelPackages) at the time of writing marks its
# drbd build broken (nixpkgs' driver.nix: `broken = kernelOlder "6.19" &&
# kernelAtLeast "6.18"`) — so, following
# https://wiki.nixos.org/wiki/ZFS's "latest ZFS-compatible kernel" recipe,
# extended with the same broken-check for drbd, this picks the newest
# kernel where neither module is broken. Deliberately not `lib.mkDefault`:
# nothing else in this repo sets boot.kernelPackages.
_: {
  den.aspects.k3s-miroir = {
    datasets."zroot/miroir".properties.mountpoint = "none";

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
          && !kernelPackages.${config.boot.zfs.package.kernelModuleAttribute}.meta.broken
          && !kernelPackages.drbd.meta.broken
        ) pkgs.linuxKernel.packages;
        latestKernelPackages = lib.last (
          lib.sort (a: b: lib.versionOlder a.kernel.version b.kernel.version) (
            builtins.attrValues compatibleKernelPackages
          )
        );
      in
      {
        # Note this might jump back and forth as kernels are added or removed.
        boot.kernelPackages = latestKernelPackages;
        boot.kernelModules = [ "drbd" ];
        boot.extraModulePackages = [ config.boot.kernelPackages.drbd ];
      };
  };
}
