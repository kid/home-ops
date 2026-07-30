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
        # TODO: drop once terragrunt-infra-catalog's feat/onepassword-secrets
        # is merged and released — pin moduleVersion to that release instead.
        moduleRef = "feat/onepassword-secrets";
        inherit (stack) dependsOn inputs;
      };
  };
}
