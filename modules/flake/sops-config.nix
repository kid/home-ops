# Generates .sops.yaml from Nix instead of hand-maintaining it: human
# recipients sourced from den.users.registry, plus one path-scoped rule per
# host that has a committed SSH key (modules/flake/provision-host-key.nix)
# and one per cluster that has a committed age key
# (modules/flake/provision-cluster-key.nix). `.sops.yaml` becomes generated
# output, like manifests/prd/** and tf-stacks/prd/**.
#
# pkgs.formats.yaml renders the attrset straight to YAML — no hand-built
# templating needed, unlike _render-lib.nix's HCL renderer.
{
  config,
  lib,
  self,
  ...
}:
let
  # Every registry user's sshKeys, not just kid's — a service account (e.g.
  # external-dns, metrics) has none, so this naturally stays human-only
  # without singling out a user by name.
  humanKeys = lib.unique (lib.concatMap (u: u.sshKeys) (lib.attrValues config.den.users.registry));

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

  # den.clusters is a flat registry (not per-system, unlike den.hosts —
  # clusters aren't tied to one architecture).
  clusterNames = builtins.attrNames (config.den.clusters or { });
  clusterPubKeyPath = cluster: secretsDir + "/clusters/${cluster}/sops-age-key.pub";

  # Same "not provisioned yet -> no rule, no error" behavior as hostRule.
  provisionedClusters = builtins.filter (
    cluster: builtins.pathExists (clusterPubKeyPath cluster)
  ) clusterNames;

  clusterRule = cluster: {
    path_regex = "secrets/clusters/${cluster}/.*";
    key_groups = [
      {
        age = humanKeys ++ [ (lib.removeSuffix "\n" (builtins.readFile (clusterPubKeyPath cluster))) ];
      }
    ];
  };

  sopsConfig = {
    creation_rules =
      map hostRule provisionedHosts
      ++ map clusterRule provisionedClusters
      ++ [
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
      renderedSopsYaml = (pkgs.formats.yaml { }).generate "sops-config.yaml" sopsConfig;
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
