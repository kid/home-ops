# Shared "dns" RouterOS stack aspect — see ros-base.nix for why this is thin.
_: {
  tf.ros-dns = {
    "terragrunt-stacks" =
      { device, ... }:
      let
        stack = device.aspect.terragruntInputs.dns;
      in
      {
        stack = "dns";
        moduleSource = "ros-dns";
        moduleVersion = "1.0.2";
        # TODO: drop once terragrunt-infra-catalog's feat/onepassword-secrets
        # is merged and released — pin moduleVersion to that release instead.
        moduleRef = "feat/onepassword-secrets";
        inherit (stack) dependsOn inputs;
      };
  };
}
