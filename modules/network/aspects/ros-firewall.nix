# Shared "firewall" RouterOS stack aspect — see ros-base.nix for why this is
# thin, except this one also does real work: it's the integration point
# between rb5009's own manual/local rules (routerosDevice.aspect.
# terragruntInputs.firewall, see modules/routerosDevices/rb5009.nix) and the
# `firewall` quirk pool (den.quirks.firewall — network/cluster/etc.-emitted
# rule fragments, collected here via modules/den/policies/pipes.nix's
# routeros-device-collect-firewall). Quirk-derived rules are placed before
# each network's manual leftovers, matching every network's pre-hoist rule
# order (confirmed against the hand-written rb5009.nix this was split out
# of) — the Terraform module keys each rendered resource as "<chain>-%03d"
# by list position, so reordering would cause spurious destroy/recreate.
{ lib, ... }:
{
  den.aspects.ros-firewall = {
    "terragrunt-stacks" =
      {
        routerosDevice,
        firewall ? [ ],
        ...
      }:
      let
        stack = routerosDevice.aspect.terragruntInputs.firewall;

        byNetwork = lib.groupBy (f: f.network) firewall;

        mergeDir =
          dir: manual:
          let
            names = lib.unique (builtins.attrNames manual ++ builtins.attrNames byNetwork);
          in
          lib.filterAttrs (_: rules: rules != [ ]) (
            lib.genAttrs names (
              name: (lib.concatMap (f: f.${dir} or [ ]) (byNetwork.${name} or [ ])) ++ (manual.${name} or [ ])
            )
          );
      in
      {
        stack = "firewall";
        moduleSource = "ros-firewall";
        moduleVersion = "1.0.3";
        # TODO: drop once terragrunt-infra-catalog's feat/onepassword-secrets
        # is merged and released — pin moduleVersion to that release instead.
        moduleRef = "feat/onepassword-secrets";
        inherit (stack) dependsOn;
        inputs = stack.inputs // {
          vlans_input_rules = mergeDir "input" stack.inputs.vlans_input_rules;
          vlans_forward_rules = mergeDir "forward" stack.inputs.vlans_forward_rules;
        };
      };
  };
}
