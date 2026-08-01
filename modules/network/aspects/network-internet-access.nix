# Turns den.networks.<name>.internetAccess into a `firewall` quirk fragment
# (den.quirks.firewall, modules/den/quirks/firewall.nix), collected onto
# every device by modules/den/policies/pipes.nix's routeros-device-collect-firewall.
# Always included on every network (den.schema.network.includes) so setting
# the plain internetAccess field is all a network needs to do.
{ lib, den, ... }:
{
  den.aspects.network-internet-access.firewall =
    { network, ... }:
    lib.optional (network.internetAccess != null) {
      network = network.name;
      forward = [
        (
          {
            action = "accept";
            out_interface_list = "WAN";
            comment = "Allow WAN";
          }
          // lib.optionalAttrs (!network.internetAccess) { disabled = true; }
        )
      ];
    };

  den.schema.network.includes = [ den.aspects.network-internet-access ];
}
