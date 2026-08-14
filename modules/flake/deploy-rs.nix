# Ongoing config pushes to already-installed hosts (deploy .#<host>), NOT
# initial install — that's nixos-anywhere-install
# (modules/flake/nixos-anywhere.nix). CLI lives in the devshell
# (modules/flake/devshell.nix); invoked by hand, never automated.
#
# Nodes are built straight from config.flake.nixosConfigurations.<name> —
# the same standard, already-evaluated NixOS system den produces from
# den.hosts. No den internals needed, unlike colmena (which would re-eval
# each host itself and need den's undocumented `mainModule` option).
#
# Hosts opt in via fleet.deploy-rs.targets.<name> on their own file (e.g.
# modules/hosts/node1.nix). test-vm is a throwaway QEMU box and is
# deliberately never added.
{
  inputs,
  lib,
  config,
  ...
}:
{
  config.flake-file.inputs.deploy-rs.url = "github:serokell/deploy-rs";

  options.fleet.deploy-rs.targets = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          hostname = lib.mkOption {
            type = lib.types.str;
            description = "SSH target host/IP for `deploy`";
          };
          sshUser = lib.mkOption {
            type = lib.types.str;
            default = "root";
          };
          remoteBuild = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Permanent per-host default; prefer the `deploy --remote-build` CLI flag for one-off overrides.";
          };
        };
      }
    );
    default = { };
    description = "Hosts opted into deploy-rs for ongoing config deploys";
  };

  config.flake.deploy.nodes = lib.mapAttrs (name: target: {
    inherit (target) hostname sshUser remoteBuild;
    profiles.system = {
      user = "root";
      path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos config.flake.nixosConfigurations.${name};
    };
  }) config.fleet.deploy-rs.targets;

  config.perSystem =
    { system, ... }:
    {
      # deploy-rs's `lib` output isn't one of flake-parts' standard
      # per-system categories, so inputs' (which only projects
      # packages/checks/devShells/etc.) doesn't cover it here.
      #
      # deployChecks returns an attrset of checks (deploy-activate,
      # deploy-schema), not a single derivation — merge it straight into
      # `checks` rather than nesting it under one name.
      checks = inputs.deploy-rs.lib.${system}.deployChecks config.flake.deploy;
    };
}
