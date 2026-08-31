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

  # den.classes.k8s-manifests is registered in modules/den/batteries/kubernetes/k8s-manifests.nix.

  # Instantiate each cluster's collected k8s-manifests content into a real
  # nixidy environment, per system (mirrors modules/den/batteries/terragrunt/terragrunt-stacks.nix's
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

  den.schema.cluster.includes = [
    den.policies.cluster-to-nixidy
  ];
}
