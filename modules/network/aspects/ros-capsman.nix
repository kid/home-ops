# Shared "capsman" RouterOS stack aspect — see ros-base.nix for why this is
# thin.
_: {
  den.aspects.ros-capsman = {
    "terragrunt-stacks" =
      { routerosDevice, ... }:
      let
        stack = routerosDevice.aspect.terragruntInputs.capsman;
      in
      {
        stack = "capsman";
        moduleSource = "ros-capsman";
        moduleVersion = "1.1.2";
        # TODO: drop once terragrunt-infra-catalog's feat/onepassword-secrets
        # is merged and released — pin moduleVersion to that release instead.
        moduleRef = "feat/onepassword-secrets";
        inherit (stack) dependsOn inputs;
      };
  };
}
