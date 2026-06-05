{ inputs, ... }:
{
  flake-file.inputs.disko.url = "github:nix-community/disko";
  flake-file.inputs.disko.inputs.nixpkgs.follows = "nixpkgs";

  ops.disko = device: {
    nixos =
      { ... }:
      {
        imports = [
          inputs.disko.nixosModules.disko
        ];

        # fileSystems."/home" = {
        #   neededForBoot = true;
        # };

        virtualisation.vmVariantWithDisko = {
          virtualisation.fileSystems."/home".neededForBoot = true;
        };

        disko.devices.disk.main = {
          inherit device;
          type = "disk";
          content = {
            type = "gpt";
            partitions = {
              ESP = {
                label = "boot";
                size = "256M";
                type = "EF00";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  extraArgs = [ "-F32" ];
                  mountpoint = "/boot/efi";
                  mountOptions = [
                    "defaults"
                  ];
                };
              };
              system = {
                label = "system";
                size = "100%";
                content = {
                  type = "btrfs";
                  extraArgs = [ "-f" ];
                  subvolumes = {
                    "/@" = {
                      mountpoint = "/";
                      mountOptions = [
                        "compress=zstd"
                        "noatime"
                      ];
                    };
                    "/@home" = {
                      mountpoint = "/home";
                      mountOptions = [
                        "compress=zstd"
                        "noatime"
                      ];
                    };
                    "/@nix" = {
                      mountpoint = "/nix";
                      mountOptions = [
                        "compress=zstd"
                        "noatime"
                      ];
                    };
                    "/@persistent" = {
                      mountpoint = "/persistent";
                      mountOptions = [
                        "compress=zstd"
                        "noatime"
                      ];
                    };
                  };
                };
              };
            };
          };
        };
      };
  };
}
