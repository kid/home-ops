# A host's NICs from its den.devices entry, statically addressed: each
# physical interface is matched by MAC, `tagged` ones become 802.1Q VLANs on
# the first interface's NIC, and only the first carries the gateway, DNS and
# NTP (the network's router, host 1). rb5009's static leases for the same
# addresses stay as reservations, for installers and the VM bootstrap image.
# The MTU goes in the .network file, not a .link one: a matching .link
# replaces 99-default.link and with it the predictable interface name.
#
# vmBridges (bridge -> network) each get a `vlan<id>` VLAN on the first NIC
# as their only port, for VMs to attach to (tf-catalog/modules/incus-k3s);
# a tagged interface on a bridged network puts its address on the bridge.
{ config, den, ... }:
{
  den.aspects.host-network.nixos =
    { host, lib, ... }:
    let
      device =
        config.den.devices.${host.name} or {
          interfaces = [ ];
          vmBridges = { };
        };
      inherit (device) interfaces;
      bridges =
        device.vmBridges
        |> lib.mapAttrsToList (
          name: network: {
            inherit name network;
            vlan = "vlan${toString config.den.networks.${network}.vlanId}";
            iface = lib.findFirst (i: i.tagged && i.network == network) null interfaces;
          }
        );
      bridgedNetworks = map (b: b.network) bridges;
      physical = lib.filter (i: !i.tagged) interfaces;
      tagged = lib.filter (i: i.tagged && !lib.elem i.network bridgedNetworks) interfaces;
      vlanName = i: lib.toLower i.network;
      netOf =
        i: config.den.environments.${config.den.networks.${i.network}.environment}.networks.${i.network};
      addressOf = i: "${i.address}/${toString (netOf i).prefix}";
      mtuOf = i: lib.optionalAttrs (i.mtu != null) { MTUBytes = i.mtu; };
      networkMtu =
        network:
        lib.optionalAttrs (config.den.networks.${network}.mtu != null) {
          MTUBytes = config.den.networks.${network}.mtu;
        };
    in
    {
      assertions = [
        {
          assertion = interfaces == [ ] || !(builtins.head interfaces).tagged;
          message = "den.devices.${host.name}: the first interface carries the VLANs and cannot itself be tagged";
        }
      ];

      systemd.network.netdevs = lib.mkIf (interfaces != [ ]) (
        (
          tagged
          |> map (
            iface:
            lib.nameValuePair "20-${vlanName iface}" {
              netdevConfig = {
                Kind = "vlan";
                Name = vlanName iface;
              };
              vlanConfig.Id = config.den.networks.${iface.network}.vlanId;
            }
          )
          |> lib.listToAttrs
        )
        // (
          bridges
          |> lib.concatMap (b: [
            (lib.nameValuePair "20-${b.vlan}" {
              netdevConfig = {
                Kind = "vlan";
                Name = b.vlan;
              };
              vlanConfig.Id = config.den.networks.${b.network}.vlanId;
            })
            (lib.nameValuePair "30-${b.name}" {
              netdevConfig = {
                Kind = "bridge";
                Name = b.name;
              };
            })
          ])
          |> lib.listToAttrs
        )
      );

      systemd.network.networks = lib.mkIf (interfaces != [ ]) (
        (
          physical
          |> lib.imap0 (
            i: iface:
            let
              router = lib.optionals (i == 0) [ ((netOf iface).methods.host 1) ];
            in
            lib.nameValuePair "10-${lib.toLower iface.network}" {
              # Physical NICs only: VLAN subinterfaces share their parent's MAC.
              matchConfig = {
                MACAddress = iface.mac;
                Kind = "!*";
                Type = "ether";
              };
              address = [ (addressOf iface) ];
              gateway = router;
              dns = router;
              ntp = router;
              vlan = lib.optionals (i == 0) (map vlanName tagged ++ map (b: b.vlan) bridges);
              linkConfig = mtuOf iface;
            }
          )
          |> lib.listToAttrs
        )
        // (
          tagged
          |> map (
            iface:
            lib.nameValuePair "20-${vlanName iface}" {
              matchConfig.Name = vlanName iface;
              address = [ (addressOf iface) ];
              linkConfig = mtuOf iface;
            }
          )
          |> lib.listToAttrs
        )
        // (
          bridges
          |> lib.concatMap (b: [
            (lib.nameValuePair "20-${b.vlan}" {
              matchConfig.Name = b.vlan;
              networkConfig = {
                Bridge = b.name;
                LinkLocalAddressing = "no";
              };
              linkConfig = networkMtu b.network;
            })
            (lib.nameValuePair "30-${b.name}" (
              {
                matchConfig.Name = b.name;
                networkConfig = {
                  LinkLocalAddressing = "no";
                  ConfigureWithoutCarrier = true;
                };
                linkConfig = networkMtu b.network;
              }
              // (
                if b.iface != null then
                  { address = [ (addressOf b.iface) ]; }
                else
                  # Nothing on the host to wait for.
                  {
                    linkConfig = networkMtu b.network // {
                      RequiredForOnline = "no";
                    };
                  }
              )
            ))
          ])
          |> lib.listToAttrs
        )
      );
    };

  den.aspects.base.includes = [ den.aspects.host-network ];
}
