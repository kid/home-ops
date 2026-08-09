# Shared "qos" RouterOS stack aspect — see ros-base.nix for why this is thin.
_: {
  den.aspects.ros-qos = {
    "terragrunt-stacks" =
      { routerosDevice, ... }:
      let
        stack = routerosDevice.aspect.terragruntInputs.qos;
      in
      {
        stack = "qos";
        moduleSource = "ros-qos";
        moduleVersion = "1.0.2";
        # TODO: drop once terragrunt-infra-catalog cuts a ros-qos release
        # containing #41 (1Password auth migration, merged but unreleased —
        # no fix:/feat: commit triggered semantic-release) — pin
        # moduleVersion to that release instead.
        moduleRef = "6cfae877ca29ef8453912356d008e287489404f9";
        inherit (stack) dependsOn inputs;
      };
  };
}
