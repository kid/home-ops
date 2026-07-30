# Shared "firewall" RouterOS stack aspect — see ros-base.nix for why this is
# thin.
_: {
  den.aspects.ros-firewall = {
    "terragrunt-stacks" =
      { device, ... }:
      let
        stack = device.aspect.terragruntInputs.firewall;
      in
      {
        stack = "firewall";
        moduleSource = "ros-firewall";
        moduleVersion = "1.0.3";
        # TODO: drop once terragrunt-infra-catalog's feat/onepassword-secrets
        # is merged and released — pin moduleVersion to that release instead.
        moduleRef = "feat/onepassword-secrets";
        inherit (stack) dependsOn inputs;
      };
  };
}
