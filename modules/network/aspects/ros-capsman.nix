# Shared "capsman" RouterOS stack aspect — see ros-base.nix for why this is
# thin.
_: {
  tf.ros-capsman = {
    "terragrunt-stacks" =
      { device, ... }:
      let
        stack = device.aspect.terragruntInputs.capsman;
      in
      {
        stack = "capsman";
        moduleSource = "ros-capsman";
        moduleVersion = "1.1.2";
        inherit (stack) dependsOn inputs;
      };
  };
}
