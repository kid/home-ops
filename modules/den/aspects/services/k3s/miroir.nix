# Node side of miroir (modules/den/aspects/kubernetes/miroir/default.nix):
# an LVM-thin pool on `settings.device`, replicated between nodes with DRBD.
#
# DRBD9 (>= 9.3.1) is needed on every node before miroir can replicate. The
# default kernel's drbd build can be marked broken in nixpkgs (driver.nix,
# e.g. for 6.18), so this picks the newest kernel where it is not.
# Deliberately not `lib.mkDefault`: nothing else in this repo sets
# boot.kernelPackages.
{ lib, ... }:
{
  den.aspects.k3s-miroir-node = {
    settings.device = lib.mkOption { type = lib.types.str; };

    miroir-nodes =
      { host, ... }:
      {
        hostname = host.name;
        device = host.settings.k3s-miroir-node.settings.device;
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
        latestKernelPackages = lib.last (
          lib.sort (a: b: lib.versionOlder a.kernel.version b.kernel.version) (
            builtins.attrValues compatibleKernelPackages
          )
        );
      in
      {
        # Note this might jump back and forth as kernels are added or removed.
        boot.kernelPackages = latestKernelPackages;
        boot.kernelModules = [
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
