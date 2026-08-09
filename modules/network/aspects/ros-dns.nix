# Shared "dns" RouterOS stack aspect — see ros-base.nix for why this is thin.
_: {
  den.aspects.ros-dns = {
    "terragrunt-stacks" =
      { routerosDevice, ... }:
      let
        stack = routerosDevice.aspect.terragruntInputs.dns;
      in
      {
        stack = "dns";
        moduleSource = "ros-dns";
        moduleVersion = "2.0.0";
        inherit (stack) dependsOn inputs;
      };
  };
}
