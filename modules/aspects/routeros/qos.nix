# Queues on a RouterOS device's WAN: the catalog's ros-qos module, called with
# the device's routerosInputs.qos (see modules/fleet/routeros/rb5009.nix).
{ lib, ... }:
let
  inherit (import ./_lib.nix { inherit lib; }) catalogModule;
in
{
  den.aspects.routeros.qos.tofu =
    { routerosDevice, ... }:
    {
      module.qos = catalogModule {
        name = "ros-qos";
        variables = [
          "bridge_name"
          "limit_rx"
          "limit_tx"
          "op_item_routeros"
          "op_vault"
          "routeros_insecure"
          "wan_interface"
        ];
        inherit (routerosDevice.aspect.routerosInputs.qos) inputs;
      };
    };
}
