# A RouterOS device's firewall: the catalog's ros-firewall module. Also the
# integration point between rb5009's own manual/local rules (routerosDevice.aspect.
# routerosInputs.firewall, see modules/fleet/routeros/rb5009.nix) and the
# `firewall` quirk pool (den.quirks.firewall — network/cluster/etc.-emitted
# rule fragments, collected here via modules/den/policies/pipes.nix's
# routeros-device-collect-firewall). Quirk-derived rules are placed before
# each network's manual leftovers, matching every network's pre-hoist rule
# order (confirmed against the hand-written rb5009.nix this was split out
# of) — the Terraform module keys each rendered resource as "<chain>-%03d"
# by list position, so reordering would cause spurious destroy/recreate.
{ lib, ... }:
let
  inherit (import ./_lib.nix { inherit lib; }) catalogModule;
in
{
  den.aspects.routeros.firewall = {
    tofu =
      {
        routerosDevice,
        firewall ? [ ],
        ...
      }:
      let
        stack = routerosDevice.aspect.routerosInputs.firewall;

        byNetwork = lib.groupBy (f: f.network) firewall;

        # lib.unique: clusters sharing a network emit identical rules (e.g.
        # cilium/bgp.nix's BGP input rule); one copy is enough.
        mergeDir =
          dir: manual:
          let
            names = lib.unique (builtins.attrNames manual ++ builtins.attrNames byNetwork);
          in
          lib.genAttrs names (
            name:
            lib.unique (lib.concatMap (f: f.${dir} or [ ]) (byNetwork.${name} or [ ]))
            ++ (manual.${name} or [ ])
          )
          |> lib.filterAttrs (_: rules: rules != [ ]);
      in
      {
        module.firewall = catalogModule {
          name = "ros-firewall";
          version = "2.1.1";
          variables = [
            "input_rules"
            "mgmt_interface_list"
            "op_item_routeros"
            "op_vault"
            "routeros_insecure"
            "vlans"
            "vlans_forward_rules"
            "vlans_input_rules"
            "wan_interface_list"
          ];
          inputs = stack.inputs // {
            vlans_input_rules = mergeDir "input" stack.inputs.vlans_input_rules;
            vlans_forward_rules = mergeDir "forward" stack.inputs.vlans_forward_rules;
          };
        };
      };
  };
}
