# Account-wide ZeroTier Central config, not RouterOS device config — lives
# outside aspects/routeros/ and is instantiated on the `environment` entity
# (den.policies.environment-to-terragrunt) rather than a routerosDevice.
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
