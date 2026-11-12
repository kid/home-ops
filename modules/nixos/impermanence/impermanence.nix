# Impermanent root: every boot starts from an empty root dataset
# (rollback-zfs.nix), and only what aspects declare through the `persist`
# and `cache` quirks (collect.nix) is bind-mounted back from /persist or
# /cache. /home is its own dataset and is kept.
{
  den,
  inputs,
  lib,
  ...
}:
{
  flake-file.inputs.impermanence.url = "github:nix-community/impermanence";

  den.aspects.impermanence = {
    includes = [
      den.aspects.impermanence.collect
      den.aspects.impermanence.rollback-zfs
    ];

    # sshd's host key — without this, wipeRootOnBoot regenerates it every
    # boot, changing the host's SSH identity on each reboot.
    persist.files = [
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
    ];

    settings.wipeRootOnBoot = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Roll the root dataset back to its empty snapshot on boot";
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
          "/var/log"
          "/var/tmp"
        ];
      };

      environment.persistence."/persist" = {
        enable = true;
        hideMounts = true;
        files = [
          "/etc/machine-id"
          # The host key of LoadCredentialEncrypted credentials.
          "/var/lib/systemd/credential.secret"
        ];
        directories = [ ];
      };
    };
  };
}
