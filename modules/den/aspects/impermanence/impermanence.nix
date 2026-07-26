# Impermanent-root aspect. Ported from nixopslab's
# modules/den/aspects/impermanence/impermanence.nix.
{
  den,
  inputs,
  lib,
  ...
}:
{
  flake-file.inputs.impermanence.url = "github:nix-community/impermanence";

  den.aspects.impermanence = {
    includes = [ den.aspects.impermanence.persist-collector ];

    settings = {
      wipeRootOnBoot = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether root is wiped to an empty ZFS snapshot on boot";
      };
      wipeHomeOnBoot = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether /home is wiped to an empty ZFS snapshot on boot";
      };
    };

    nixos = {
      imports = [ inputs.impermanence.nixosModules.impermanence ];

      environment.persistence."/cache" = {
        enable = true;
        persistentStoragePath = "/cache";
        hideMounts = true;
        directories = [
          "/var/lib/nixos"
          "/var/tmp"
        ];
      };

      environment.persistence."/persist" = {
        enable = true;
        hideMounts = true;
        files = [ "/etc/machine-id" ];
        directories = [ ];
      };
    };
  };
}
