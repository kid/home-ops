# Shared "qos" RouterOS stack aspect — see ros-base.nix for why this is thin.
_: {
  tf.ros-qos = {
    "terragrunt-stacks" =
      { device, ... }:
      let
        stack = device.aspect.terragruntInputs.qos;
      in
      {
        stack = "qos";
        moduleSource = "ros-qos";
        moduleVersion = "1.0.2";
        # TODO: drop once terragrunt-infra-catalog's feat/onepassword-secrets
        # is merged and released — pin moduleVersion to that release instead.
        moduleRef = "feat/onepassword-secrets";
        inherit (stack) dependsOn inputs;
      };
  };
}
