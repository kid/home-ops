# DNS on a RouterOS device: the catalog's ros-dns module, called with the
# device's routerosInputs.dns (see modules/fleet/routeros/rb5009.nix).
{ lib, ... }:
let
  inherit (import ./_lib.nix { inherit lib; }) catalogModule;
in
{
  den.aspects.routeros.dns.tofu =
    { routerosDevice, ... }:
    {
      module.dns = catalogModule {
        name = "ros-dns";
        variables = [
          "dns_static_records"
          "dns_upstream_servers"
          "op_item_routeros"
          "op_vault"
          "routeros_insecure"
        ];
        inherit (routerosDevice.aspect.routerosInputs.dns) inputs;
      };
    };
}
