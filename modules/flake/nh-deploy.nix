# nix run .#deploy / `deploy` in the devshell — ongoing config push to an
# already-installed host over SSH (host must already exist via
# nixos-anywhere-install). Hosts opt in via fleet.nh.targets.<name>.
{ lib, config, ... }:
{
  config.flake-file.inputs.nh.url =
    "github:nix-community/nh/d9192c1521a067eeaa5669964fb8ae7816d4787c";

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
          microvmHost = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "For a microvm.nix guest: the fleet.nh.targets name of its hypervisor. `deploy` then uses the guest's microvm.deploy.* scripts instead of nh";
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

          # nh cannot switch a microvm.nix guest (read-only shared store, no
          # nix-daemon): build and install on the hypervisor instead.
          microvmHost=$(nix eval --raw ".#nhTargets.$host.microvmHost" 2>/dev/null) || true
          if [[ -n "$microvmHost" ]]; then
            hvHostname=$(nix eval --raw ".#nhTargets.$microvmHost.hostname")
            hvUser=$(nix eval --raw ".#nhTargets.$microvmHost.sshUser" 2>/dev/null) || true
            hvTarget="''${hvUser:-$(whoami)}@$hvHostname"
            deployAttr=".#nixosConfigurations.$host.config.microvm.deploy"

            case "$mode" in
              switch)
                echo "==> Deploying microvm '$host' (switch) via $hvTarget, then $target..."
                exec nix run "$deployAttr.rebuild" -- "$hvTarget" "$target" --use-remote-sudo
                ;;
              boot)
                echo "==> Installing microvm '$host' on $hvTarget (active after 'systemctl restart microvm@$host')..."
                exec nix run "$deployAttr.installOnHost" -- "$hvTarget" --use-remote-sudo
                ;;
              *)
                echo "error: a microvm guest only supports switch and boot" >&2
                exit 1
                ;;
            esac
          fi

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
