# Cluster -> nixidy collection policy.
#
# Adapted from nixopslab's modules/den/policies/cluster.nix. Unlike
# nixopslab, there's no separate `flake-to-clusters`/`cluster-aspect`
# policy here: `env-to-clusters` (modules/den/policies/fleet.nix) already
# fans environment -> cluster, and den.schema.cluster's `aspect` field
# (modules/den/schema/clusters.nix) already self-provides
# `den.aspects.<cluster.name>` via den's built-in selfProvide mechanism —
# the same convention already used for `network`/`routerosDevice`/`environment` in
# this repo, so no explicit "walk den.aspects by name" policy is needed.
{
  lib,
  den,
  config,
  inputs,
  self,
  withSystem,
  ...
}:
{
  flake-file.inputs.nixidy = {
    url = "github:arnarg/nixidy";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  # den.classes.k8s-manifests is registered in modules/flake/k8s.nix.

  # Instantiate each cluster's collected k8s-manifests content into a real
  # nixidy environment, per system (mirrors modules/terragrunt/collect.nix's
  # routeros-device-to-terragrunt: den.lib.policy.instantiate on a class, walking the
  # cluster's own aspect-includes chain). Unlike that pipeline, nixidy's own
  # module system expects the den-wrapped `{ imports = [...]; }` module list
  # verbatim — no unwrapping to plain data here.
  den.policies.cluster-to-nixidy =
    { cluster, ... }:
    map (
      system:
      den.lib.policy.instantiate {
        name = "${cluster.name}-nixidy";
        class = "k8s-manifests";
        intoAttr = [
          "nixidyEnvs"
          system
          cluster.name
        ];
        instantiate =
          { modules, ... }:
          withSystem system (
            { pkgs, ... }:
            inputs.nixidy.lib.mkEnv {
              inherit pkgs modules;
              charts = self.chartsDerivations.${system};
            }
          );
      }
    ) (lib.unique config.systems);

  # Cluster -> openbao-items collection policy. Unlike cluster-to-nixidy,
  # this needs plain Nix data (not a real nixidy module list), so it follows
  # modules/terragrunt/collect.nix's routeros-device-to-terragrunt technique
  # instead: a real per-aspect lib.evalModules pass (den also injects an
  # anonymous, key-less companion module alongside any quirk-requesting
  # entry — filter on `m ? key`, per that file's own comment). Unlike
  # terragrunt-stacks, openbao-items content needs no per-entry key to
  # disambiguate by (Terraform's own vault_kv_secret_v2 `for_each` keys by
  # secret path) — just a flat list of every included aspect's item spec.
  den.policies.cluster-to-openbao-items =
    { cluster, ... }:
    [
      (den.lib.policy.instantiate {
        name = "${cluster.name}-openbao-items";
        class = "openbao-items";
        instantiate =
          { modules, ... }:
          map (
            m:
            (lib.evalModules {
              modules = [
                (builtins.head m.imports)
                { _module.freeformType = lib.types.attrsOf lib.types.raw; }
              ];
              specialArgs = {
                inherit cluster;
              };
            }).config
          ) (builtins.filter (m: m ? key) modules);
        intoAttr = [
          "openbaoItems"
          cluster.name
        ];
      })
    ];

  den.schema.cluster.includes = [
    den.policies.cluster-to-nixidy
    den.policies.cluster-to-openbao-items
  ];
}
