# Single-disk ZFS layout. Adapted from nixopslab's
# modules/den/aspects/disko/zfs-disk-single.nix — disk partitioning is
# identical regardless of VM vs. bare metal; dropped `imageSize` (an
# image-builder-only option, meaningless against a real disk's actual size)
# and the `virtualisation.vmVariantWithDisko` block (VM-only).
#
# `settings.device_id` must be set per-host to the target machine's real
# stable disk identifier (e.g. "/dev/disk/by-id/nvme-..."), confirmed once
# the real hardware is known — see modules/hosts/node1.nix.
{ den, lib, ... }:
let
  emptySnapshot =
    name: "zfs list -t snapshot -H -o name | grep -E '^${name}@empty$' || zfs snapshot ${name}@empty";
in
{
  den.aspects.disko.zfs-disk-single.root.nixos = {
    boot.supportedFilesystems = [ "zfs" ];
    boot.zfs = {
      devNodes = "/dev/disk/by-id";
      forceImportRoot = false;
      forceImportAll = false;
    };
    services.zfs = {
      autoScrub.enable = true;
      trim.enable = true;
    };
  };

  den.aspects.disko.zfs-disk-single = {
    includes = [
      den.aspects.disko
      den.aspects.disko.zfs-disk-single.root
    ];

    settings.device_id = lib.mkOption {
      type = lib.types.str;
      description = "Stable disk identifier disko partitions (e.g. /dev/disk/by-id/nvme-...)";
    };

    nixos =
      { host, ... }:
      let
        deviceId = host.settings.disko.zfs-disk-single.settings.device_id;
      in
      {
        disko.devices = {
          disk.disk0 = {
            type = "disk";
            device = deviceId;
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
              k8s = {
                type = "zfs_fs";
                options.mountpoint = "none";
              };

              reserved = {
                type = "zfs_fs";
                options = {
                  mountpoint = "none";
                  reservation = "256M";
                };
              };

              "local/root" = {
                type = "zfs_fs";
                mountpoint = "/";
                options.mountpoint = "legacy";
                postCreateHook = "${emptySnapshot "zroot/local/root"} && zfs snapshot zroot/local/root@lastboot";
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

              "local/containers" = {
                type = "zfs_fs";
                options = {
                  mountpoint = "none";
                  recordsize = "128K";
                };
              };
            };
          };
        };

        fileSystems."/".neededForBoot = true;
        fileSystems."/nix".neededForBoot = true;
        fileSystems."/home".neededForBoot = true;
        fileSystems."/persist".neededForBoot = true;
        fileSystems."/cache".neededForBoot = true;
      };
  };
}
