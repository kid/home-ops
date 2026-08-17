# Generates .sops.yaml from Nix instead of hand-maintaining it: two static
# human recipients, plus one path-scoped rule per host that has a committed
# SSH key (modules/flake/provision-host-key.nix). `.sops.yaml` becomes
# generated output, like manifests/prd/** and tf-stacks/prd/**.
#
# JSON is valid YAML 1.2, so builtins.toJSON + `yq -y` (JSON-in, YAML-out) is
# enough to render — no hand-built YAML templating needed, unlike
# _render-lib.nix's HCL renderer.
{
  config,
  lib,
  self,
  ...
}:
let
  # The source of truth for these two recipients — previously only present
  # as literal strings inside the hand-maintained .sops.yaml.
  humans = [
    {
      name = "kid-vulkan";
      key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAcnmLrPeTJeKsasfU0qn4sP4lBNeOUgRG4iZDS8nyEo kid@vulkan";
    }
    {
      name = "kid-fw13";
      key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHIM3nsk3HxvEcplSqwynh9V2NzlYdI10mrR746SiJZb kid@fw13";
    }
  ];
  humanKeys = map (h: h.key) humans;

  secretsDir = ../../secrets;
  hostPubKeyPath = host: secretsDir + "/hosts/${host}/ssh_host_ed25519_key.pub";

  hostNames = lib.unique (
    lib.concatMap (system: builtins.attrNames (config.den.hosts.${system} or { })) config.systems
  );

  # A host without a committed key yet (not provisioned via
  # provision-host-key) just doesn't get a rule — no error.
  provisionedHosts = builtins.filter (host: builtins.pathExists (hostPubKeyPath host)) hostNames;

  hostRule = host: {
    path_regex = "secrets/hosts/${host}/.*";
    key_groups = [
      {
        age = humanKeys ++ [ (lib.removeSuffix "\n" (builtins.readFile (hostPubKeyPath host))) ];
      }
    ];
  };

  sopsConfig = {
    creation_rules = map hostRule provisionedHosts ++ [
      {
        key_groups = [ { age = humanKeys; } ];
      }
    ];
    stores.yaml.indent = 2;
  };
in
{
  perSystem =
    { pkgs, config, ... }:
    let
      sopsConfigJson = pkgs.writeText "sops-config.json" (builtins.toJSON sopsConfig);
      renderedSopsYaml = pkgs.runCommandLocal "sops-config-rendered" {
        nativeBuildInputs = [ pkgs.yq ];
      } "yq -y . ${sopsConfigJson} > $out";
    in
    {
      packages.write-sops-config = pkgs.writeShellApplication {
        name = "write-sops-config";
        text = ''
          install -m 644 "${renderedSopsYaml}" .sops.yaml
          echo "==> Wrote .sops.yaml"
        '';
      };

      apps.write-sops-config = {
        type = "app";
        program = "${config.packages.write-sops-config}/bin/write-sops-config";
      };

      checks.sops-config =
        pkgs.runCommandLocal "sops-config-check" { nativeBuildInputs = [ pkgs.diffutils ]; }
          ''
            if ! diff -q "${self}/.sops.yaml" "${renderedSopsYaml}"; then
              echo ".sops.yaml is stale — run: nix run .#write-sops-config" >&2
              exit 1
            fi
            touch $out
          '';
    };
}
