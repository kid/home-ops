# Shared "capsman" RouterOS stack aspect — see ros-base.nix for why this is
# thin.
_: {
  den.aspects.routeros.capsman = {
    "terragrunt-stacks" =
      { routerosDevice, ... }:
      let
        stack = routerosDevice.aspect.terragruntInputs.capsman;
      in
      {
        stack = "capsman";
        moduleSource = "ros-capsman";
        moduleVersion = "1.1.3";
        inherit (stack) dependsOn inputs;
      };
  };
}
