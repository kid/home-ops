# Shared "dns" RouterOS stack aspect — see ros-base.nix for why this is thin.
{ tf, ... }:
{
  tf.ros-dns = {
    "terragrunt-stacks" =
      { device, ... }:
      let
        stack = device.aspect.terragruntInputs.dns;
      in
      {
        stack = "dns";
        moduleSource = "ros//dns";
        inherit (stack) dependsOn inputs;
      };
  };
}
