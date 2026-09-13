# Shared "zerotier" RouterOS stack aspect — see ros-base.nix for why this is
# thin. Joins the device to the ZeroTier network created by the
# zerotier-network stack (modules/den/aspects/zerotier/network.nix,
# instantiated on the "prd" environment, not a routerosDevice).
_: {
  den.aspects.routeros.zerotier = {
    "terragrunt-stacks" =
      { routerosDevice, ... }:
      let
        stack = routerosDevice.aspect.terragruntInputs.zerotier;
      in
      {
        stack = "zerotier";
        moduleSource = "ros-zerotier";
        moduleVersion = "1.0.0";
        inherit (stack) dependsOn inputs;
      };
  };
}
