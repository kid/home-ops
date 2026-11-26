# Single-disk btrfs layout: an ESP and one btrfs partition whose subvolumes
# provide the same mount points as den.aspects.disk.zfs (/, /nix, /home,
# /persist, /cache), so nothing above the disk layer knows which layout a
# host uses. den.aspects.impermanence.rollback-btrfs recreates the root
# subvolume on boot. Imports disko itself, so a host only includes this aspect
# and sets `settings.disk.btrfs.device`; the other settings reproduce existing
# disks' partition and subvolume names without a reformat.
{ inputs, lib, ... }:
{
  den.aspects.disk.btrfs = {
    settings = {
      device = lib.mkOption {
        type = lib.types.str;
        description = "Stable disk identifier disko partitions (e.g. /dev/disk/by-id/nvme-...)";
      };
      partitionName = lib.mkOption {
        type = lib.types.str;
        default = "root";
        description = "GPT partition name; disko labels it disk-main-<name>, which fileSystems and rollback-btrfs mount by";
      };
      subvolumePrefix = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Prefix of every subvolume name; \"@/\" nests them under an @ subvolume";
      };
      persistSubvolume = lib.mkOption {
        type = lib.types.str;
        default = "persist";
        description = "Name of the subvolume mounted at /persist, after the prefix";
      };
    };

    nixos =
      { host, lib, ... }:
      let
        cfg = host.settings.disk.btrfs;
        sub = n: "${cfg.subvolumePrefix}${n}";
        parent = cfg.subvolumePrefix |> lib.removePrefix "/" |> lib.removeSuffix "/";
        mountOptions = [
          "compress=zstd"
          "noatime"
        ];
      in
      {
        imports = [ inputs.disko.nixosModules.disko ];

        boot.supportedFilesystems.btrfs = true;
        boot.initrd.supportedFilesystems.btrfs = true;

        services.btrfs.autoScrub = {
          enable = true;
          fileSystems = [ "/" ];
          interval = "weekly";
        };

        disko.devices.disk.main = {
          type = "disk";
          inherit (cfg) device;
          imageSize = "10G";
          content = {
            type = "gpt";
            partitions = {
              ESP = {
                priority = 1;
                name = "ESP";
                label = "boot";
                start = "1M";
                end = "512M";
                type = "EF00";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot";
                  mountOptions = [ "umask=0077" ];
                };
              };
              ${cfg.partitionName} = {
                size = "100%";
                content = {
                  type = "btrfs";
                  extraArgs = [
                    "-L"
                    "nixos"
                    "-f"
                  ];
                  subvolumes = lib.optionalAttrs (parent != "") { ${parent} = { }; } // {
                    ${sub "root"} = {
                      inherit mountOptions;
                      mountpoint = "/";
                    };
                    ${sub "nix"} = {
                      inherit mountOptions;
                      mountpoint = "/nix";
                    };
                    ${sub "home"} = {
                      inherit mountOptions;
                      mountpoint = "/home";
                    };
                    ${sub cfg.persistSubvolume} = {
                      inherit mountOptions;
                      mountpoint = "/persist";
                    };
                    ${sub "cache"} = {
                      inherit mountOptions;
                      mountpoint = "/cache";
                    };
                  };
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

        # system.build.vmWithDisko rebuilds fileSystems from scratch under
        # virtualisation.fileSystems: re-state impermanence's neededForBoot
        # requirement there, as disk.zfs does.
        virtualisation.vmVariantWithDisko.virtualisation.fileSystems = {
          "/persist".neededForBoot = true;
          "/cache".neededForBoot = true;
        };
      };
  };
}
