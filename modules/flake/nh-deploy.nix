# nix run .#deploy / `deploy` in the devshell — ongoing config push to an
# already-installed host over SSH (host must already exist via
# nixos-anywhere-install). Hosts opt in via fleet.nh.targets.<name>.
{ lib, config, ... }:
{
  config.flake-file.inputs.nh.url = "github:nix-community/nh";

  options.fleet.nh.targets = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          hostname = lib.mkOption {
            type = lib.types.str;
            description = "SSH target host/IP for `deploy`";
          };
          sshUser = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "SSH user for `deploy`; falls back to the invoking user if unset";
          };
        };
      }
    );
    default = { };
    description = "Hosts opted into nh --target-host for ongoing config deploys";
  };

  # den.devices isn't a top-level flake output, so a script can't reach it
  # (or fleet.nh.targets) via `nix eval .#...` without this.
  config.flake.nhTargets = config.fleet.nh.targets;

  config.perSystem =
    {
      config,
      inputs',
      pkgs,
      ...
    }:
    {
      packages.deploy = pkgs.writeShellApplication {
        name = "deploy";
        runtimeInputs = [ inputs'.nh.packages.default ];
        text = ''
          host=''${1:?usage: deploy <host> [switch|boot|test|build]}
          mode=''${2:-switch}

          hostname=$(nix eval --raw ".#nhTargets.$host.hostname") || {
            echo "error: no fleet.nh.targets.$host entry" >&2
            exit 1
          }
          sshUser=$(nix eval --raw ".#nhTargets.$host.sshUser" 2>/dev/null) || true
          sshUser=''${sshUser:-$(whoami)}
          target="$sshUser@$hostname"

          echo "==> Deploying '$host' ($mode) to $target via nh..."
          # -H must be explicit: with --target-host set but -H unset, nh
          # deploys nixosConfigurations.<ssh-host-string>, not <host>.
          # --elevation-strategy: nh otherwise prompts for a sudo password
          # regardless of remote NOPASSWD config.
          exec nh os "$mode" -H "$host" --target-host "$target" --elevation-strategy passwordless .
        '';
      };

      apps.deploy = {
        type = "app";
        program = "${config.packages.deploy}/bin/deploy";
      };
    };
}
