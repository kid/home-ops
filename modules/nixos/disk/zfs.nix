# Single-disk ZFS layout: an ESP and the zroot pool, whose local/root dataset
# carries the @empty snapshot den.aspects.impermanence rolls back to on boot.
# Imports disko and disko-zfs itself, so a host only includes this aspect and
# sets `settings.disk.zfs.device` to the machine's stable disk identifier.
{
  den,
  inputs,
  lib,
  ...
}:
let
  emptySnapshot =
    name: "zfs list -t snapshot -H -o name | grep -E '^${name}@empty$' || zfs snapshot ${name}@empty";
in
{
  flake-file.inputs.disko = {
    # Pinned to nix-community/disko#1277 (unmerged): fixes make-disk-image.nix
    # passing an aggregated module tree as vmTools' `kernel` arg, which broke
    # against a nixpkgs vmTools API change (kernel/kernelModules split) —
    # needed for system.build.vmWithDisko (see modules/hosts/test-vm.nix).
    # Switch back to nix-community/disko once merged upstream.
    url = "github:AlexLov/disko";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  # Manages ZFS datasets declaratively on every activation/boot (not just at
  # disko's install-time format), so aspects can request datasets they need
  # via the `datasets` quirk (see zfs-datasets-collector.nix) without a
  # reformat. Auto-adopts datasets already declared under disko.devices.
  flake-file.inputs.disko-zfs = {
    url = "github:numtide/disko-zfs";
    inputs.nixpkgs.follows = "nixpkgs";
    inputs.flake-parts.follows = "flake-parts";
    inputs.disko.follows = "disko";
  };

  den.aspects.disk.zfs = {
    includes = [ den.aspects.disk.zfs.collect ];

    settings.device = lib.mkOption {
      type = lib.types.str;
      description = "Stable disk identifier disko partitions (e.g. /dev/disk/by-id/nvme-...)";
    };

    nixos =
      { host, lib, ... }:
      {
        imports = [
          inputs.disko.nixosModules.disko
          inputs.disko-zfs.nixosModules.default
        ];
        disko.zfs.enable = true;

        boot.supportedFilesystems = [ "zfs" ];
        # mkDefault throughout: disko's own vmVariantWithDisko (used by
        # vmWithDisko, see modules/hosts/test-vm.nix) needs to override these to
        # import by uuid and force-import, since /dev/disk/by-id is empty in
        # qemu VMs.
        boot.zfs = {
          devNodes = lib.mkDefault "/dev/disk/by-id";
          forceImportRoot = lib.mkDefault false;
          forceImportAll = lib.mkDefault false;
        };
        services.zfs = {
          autoScrub.enable = true;
          trim.enable = true;
        };

        disko.devices = {
          disk.disk0 = {
            type = "disk";
            inherit (host.settings.disk.zfs) device;
            content = {
              type = "gpt";
              partitions = {
                ESP = {
                  size = "500M";
                  type = "EF00";
                  content = {
                    type = "filesystem";
                    format = "vfat";
                    mountpoint = "/boot";
                  };
                };
                root = {
                  size = "100%";
                  content = {
                    type = "zfs";
                    pool = "zroot";
                  };
                };
              };
            };
          };

          zpool.zroot = {
            type = "zpool";
            options = {
              ashift = "12";
              autotrim = "on";
            };
            rootFsOptions = {
              acltype = "posixacl";
              canmount = "off";
              checksum = "edonr";
              compression = "zstd";
              xattr = "sa";
              "com.sun:auto-snapshot" = "false";
            };
            postCreateHook = emptySnapshot "zroot";

            datasets = {
              reserved = {
                type = "zfs_fs";
                options = {
                  mountpoint = "none";
                  reservation = "256M";
                };
              };

              # Taken before anything writes to the root: the snapshot
              # den.aspects.impermanence.rollback-zfs restores on every boot.
              "local/root" = {
                type = "zfs_fs";
                mountpoint = "/";
                options.mountpoint = "legacy";
                postCreateHook = emptySnapshot "zroot/local/root";
              };

              "local/nix" = {
                type = "zfs_fs";
                mountpoint = "/nix";
                options.mountpoint = "legacy";
              };

              "local/home" = {
                type = "zfs_fs";
                mountpoint = "/home";
                options.mountpoint = "legacy";
              };

              "local/persist" = {
                type = "zfs_fs";
                mountpoint = "/persist";
                options.mountpoint = "legacy";
              };

              "local/cache" = {
                type = "zfs_fs";
                mountpoint = "/cache";
                options.mountpoint = "legacy";
              };

              # containerd's datasets (local/containerd + its snapshotter
              # child) are declared by den.aspects.k3s-containerd via the
              # `datasets` quirk instead of here — see
              # zfs-datasets-collector.nix. That lets disko-zfs create them
              # post-install, without a reformat.
            };
          };
        };

        fileSystems."/".neededForBoot = true;
        fileSystems."/nix".neededForBoot = true;
        fileSystems."/home".neededForBoot = true;
        fileSystems."/persist".neededForBoot = true;
        fileSystems."/cache".neededForBoot = true;

        # system.build.vmWithDisko rebuilds fileSystems from scratch under
        # virtualisation.fileSystems (see disko's docs/interactive-vm.md) —
        # the neededForBoot overrides above don't carry over into it, so
        # impermanence's own assertion (persist/cache must be neededForBoot)
        # needs re-stating here too.
        virtualisation.vmVariantWithDisko.virtualisation.fileSystems = {
          "/persist".neededForBoot = true;
          "/cache".neededForBoot = true;
        };
      };
  };
}
