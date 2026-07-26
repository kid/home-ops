# Shared "base" RouterOS stack aspect — thin: the actual per-device inputs
# (ethernet_interfaces, ip_addresses, dhcp_servers, vlans, …) live on the
# device's own self-aspect (tf.<device>.terragruntInputs.base, see
# modules/devices/rb5009.nix), precomputed there because cidrhost()-style
# arithmetic needs modules/network/lib.nix's cidrLib, which den's aspect
# content functions can't see (only entity-kind scope bindings like `device`
# are — see modules/terragrunt/collect.nix).
_: {
  tf.ros-base = {
    "terragrunt-stacks" =
      { device, ... }:
      let
        stack = device.aspect.terragruntInputs.base;
      in
      {
        stack = "base";
        moduleSource = "ros-base";
        moduleVersion = "1.0.3";
        inherit (stack) dependsOn inputs;
      };
  };
}
