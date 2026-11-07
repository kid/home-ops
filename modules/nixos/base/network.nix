# A host's NICs from its den.devices entry: DHCP on each, matched by MAC, and
# the default route only from the first (primary) one. The MTU goes in the
# .network file, not a .link one: a matching .link replaces 99-default.link
# and with it the predictable interface name.
{ config, den, ... }:
{
  den.aspects.host-network.nixos =
    { host, lib, ... }:
    let
      inherit (config.den.devices.${host.name} or { interfaces = [ ]; }) interfaces;
    in
    {
      systemd.network.networks = lib.mkIf (interfaces != [ ]) (
        interfaces
        |> lib.imap0 (
          i: iface:
          lib.nameValuePair "10-${lib.toLower iface.network}" {
            # Physical NICs only: VLAN subinterfaces share their parent's MAC.
            matchConfig = {
              MACAddress = iface.mac;
              Kind = "!*";
              Type = "ether";
            };
            networkConfig.DHCP = "yes";
            dhcpV4Config.UseGateway = i == 0;
            linkConfig = lib.optionalAttrs (iface.mtu != null) { MTUBytes = iface.mtu; };
          }
        )
        |> lib.listToAttrs
      );
    };

  den.aspects.base.includes = [ den.aspects.host-network ];
}
