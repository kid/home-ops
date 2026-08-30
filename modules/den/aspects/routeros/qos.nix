# Shared "qos" RouterOS stack aspect — see ros-base.nix for why this is thin.
_: {
  den.aspects.ros-qos = {
    "terragrunt-stacks" =
      { routerosDevice, ... }:
      let
        stack = routerosDevice.aspect.terragruntInputs.qos;
      in
      {
        stack = "qos";
        moduleSource = "ros-qos";
        moduleVersion = "2.0.0";
        inherit (stack) dependsOn inputs;
      };
  };
}
