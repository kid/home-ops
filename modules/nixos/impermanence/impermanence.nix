# Impermanent-root aspect.
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

    # sshd's host key — without this, wipeRootOnBoot regenerates it every
    # boot, changing the host's SSH identity on each reboot.
    persist.files = [
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
    ];

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

      # ed25519 only — no RSA host key.
      services.openssh.hostKeys = lib.mkForce [
        {
          path = "/etc/ssh/ssh_host_ed25519_key";
          type = "ed25519";
        }
      ];

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
