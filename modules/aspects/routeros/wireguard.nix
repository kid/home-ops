# Shared "wireguard" RouterOS stack aspect — see ros-base.nix for why this is thin.
_: {
  den.aspects.routeros.wireguard = {
    "terragrunt-stacks" =
      { routerosDevice, ... }:
      let
        stack = routerosDevice.aspect.terragruntInputs.wireguard;
      in
      {
        stack = "wireguard";
        localModule = "ros-wireguard";
        inherit (stack) dependsOn inputs;
      };
  };
}
