# CAPsMAN on a RouterOS device: the catalog's ros-capsman module, called with
# the device's routerosInputs.capsman (see modules/fleet/routeros/rb5009.nix).
{ lib, ... }:
let
  inherit (import ./_lib.nix { inherit lib; }) catalogModule;
in
{
  den.aspects.routeros.capsman.tofu =
    { routerosDevice, ... }:
    {
      module.capsman = catalogModule {
        name = "ros-capsman";
        version = "1.1.4";
        variables = [
          "bridge_name"
          "capsman_interfaces"
          "op_item_routeros"
          "op_item_wifi"
          "op_vault"
          "passphrase_groups"
          "routeros_insecure"
        ];
        inherit (routerosDevice.aspect.routerosInputs.capsman) inputs;
      };
    };
}
