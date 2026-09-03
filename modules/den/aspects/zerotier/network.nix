# "zerotier-network" environment-scoped terragrunt-stack aspect — not a
# RouterOS aspect (lives outside modules/den/aspects/routeros/ on purpose):
# this is account-wide ZeroTier Central SaaS config (network/routes/member
# authorization), not RouterOS device config, so it's instantiated on the
# `environment` entity via den.policies.environment-to-terragrunt
# (modules/den/batteries/terragrunt/terragrunt-stacks.nix) rather than on a
# routerosDevice. See modules/den/environments.nix for the "prd" instance
# data and modules/den/aspects/routeros/zerotier.nix for the RouterOS side
# that joins the network this creates.
_: {
  den.aspects.zerotierNetwork = {
    "terragrunt-stacks" =
      { environment, ... }:
      let
        stack = environment.aspect.terragruntInputs."zerotier-network";
      in
      {
        stack = "zerotier-network";
        moduleSource = "zerotier-network";
        moduleVersion = "1.0.0";
        inherit (stack) dependsOn inputs;
      };
  };
}
