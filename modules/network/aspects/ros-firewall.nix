# Shared "firewall" RouterOS stack aspect — see ros-base.nix for why this is
# thin.
{ tf, ... }:
{
  tf.ros-firewall = {
    "terragrunt-stacks" =
      { device, ... }:
      let
        stack = device.aspect.terragruntInputs.firewall;
      in
      {
        stack = "firewall";
        moduleSource = "ros//firewall";
        inherit (stack) dependsOn inputs;
      };
  };
}
