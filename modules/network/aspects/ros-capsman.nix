# Shared "capsman" RouterOS stack aspect — see ros-base.nix for why this is
# thin.
{ tf, ... }:
{
  tf.ros-capsman = {
    "terragrunt-stacks" =
      { device, ... }:
      let
        stack = device.aspect.terragruntInputs.capsman;
      in
      {
        stack = "capsman";
        moduleSource = "ros//capsman";
        inherit (stack) dependsOn inputs;
      };
  };
}
