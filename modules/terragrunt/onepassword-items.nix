# Folds config.flake.onepasswordItems (modules/den/policies/cluster.nix's
# cluster-to-onepassword-items policy) into config.flake.terragruntStacks
# (modules/terragrunt/collect.nix's home, though this policy is defined
# alongside it rather than in that file, to keep collect.nix's existing
# routerosDevice-only logic untouched) as one combined leaf per cluster, so
# modules/terragrunt/devshell.nix's existing write-terragrunt/
# checks.terragrunt machinery renders and checks it with no further
# generalization needed — the aspect-includes walking already happened in
# cluster-to-onepassword-items; this just reshapes its already-collected
# result into a "terragrunt-stacks"-class leaf via den's own
# intoAttr mechanism (the only thing that can safely merge into
# flake.terragruntStacks alongside collect.nix's own routerosDevice
# contributions — a plain second `flake.terragruntStacks = ...;` module
# collides, since flake-parts requires undeclared flake outputs to have
# exactly one definition site).
#
# One leaf per cluster, not one per app: every app's 1Password items share a
# single Terraform state, since each is small and none need an independent
# apply.
{
  config,
  lib,
  den,
  ...
}:
{
  den.policies.cluster-to-onepassword-terragrunt =
    { cluster, ... }:
    [
      (den.lib.policy.instantiate {
        name = "${cluster.name}-onepassword-items-terragrunt";
        class = "onepassword-items";
        instantiate =
          _:
          let
            items = config.flake.onepasswordItems.${cluster.name} or [ ];
          in
          lib.optionalAttrs (items != [ ]) {
            onepassword-items = {
              stack = "onepassword-items";
              localModule = "onepassword-items";
              dependsOn = [ ];
              inputs.items = items;
            };
          };
        intoAttr = [
          "terragruntStacks"
          cluster.name
        ];
      })
    ];

  den.schema.cluster.includes = [ den.policies.cluster-to-onepassword-terragrunt ];
}
