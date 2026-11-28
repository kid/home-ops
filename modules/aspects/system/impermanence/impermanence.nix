# Impermanent root: every boot starts from an empty root, rolled back by the
# host's disk layout (rollback-zfs.nix for disk.zfs, rollback-btrfs.nix for
# disk.btrfs), and only what aspects declare through the `persist` and
# `cache` quirks (collect.nix) is bind-mounted back from /persist or /cache.
# /home is its own dataset or subvolume and is kept.
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
      den.aspects.impermanence.rollback-btrfs
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

    nixos =
      { config, ... }:
      let
        credentialSecret = "/var/lib/systemd/credential.secret";
      in
      {
        imports = [
          inputs.impermanence.nixosModules.impermanence
          # sops-nix decrypts with the host key in an activation script, which
          # nothing orders after impermanence's bind mount of
          # /etc/ssh/ssh_host_ed25519_key: read it from /persist directly.
          (
            { options, ... }:
            {
              config = lib.optionalAttrs (options ? sops) {
                sops.age.sshKeyPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];
              };
            }
          )
        ];

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
            credentialSecret
          ];
          directories = [ ];
        };

        # impermanence symlinks a persisted file that doesn't exist yet, and
        # systemd refuses to read or create its host key through a symlink
        # (ELOOP), failing every LoadCredentialEncrypted unit. Create the key in
        # /persist first, and drop a symlink left by an earlier activation, so
        # persist-files bind-mounts it.
        system.activationScripts.credential-secret = {
          deps = [ "createPersistentStorageDirs" ];
          text = ''
            if [ ! -e /persist${credentialSecret} ]; then
              mkdir -p /persist${dirOf credentialSecret}
              SYSTEMD_CREDENTIAL_SECRET=/persist${credentialSecret} \
                ${config.systemd.package}/bin/systemd-creds setup
            fi
            if [ -L ${credentialSecret} ]; then
              rm ${credentialSecret}
            fi
          '';
        };
        system.activationScripts.persist-files.deps = [ "credential-secret" ];
      };
  };
}
