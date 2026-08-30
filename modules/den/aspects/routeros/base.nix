# Shared "base" RouterOS stack aspect — thin: the actual per-device inputs
# (ethernet_interfaces, ip_addresses, dhcp_servers, vlans, …) live on the
# device's own self-aspect (den.aspects.<routerosDevice>.terragruntInputs.base,
# see modules/routerosDevices/rb5009.nix), precomputed there because
# cidrhost()-style arithmetic needs modules/network/lib.nix's cidrLib, which
# den's aspect content functions can't see (only entity-kind scope bindings
# like `routerosDevice` are — see modules/terragrunt/collect.nix).
#
# routeros_users/routeros_groups are merged in here instead, sourced
# directly from den.users.registry/den.groups (modules/den/schema/users.nix,
# groups.nix) — plain registry reads, not resolve.to/quirks, since this is a
# single producer/single consumer relationship the same way
# den.environments/den.networks are already read directly elsewhere in this
# repo (see the plan for why the NixOS side, which needs quirks/pipes, is
# different).
{ den, lib, ... }:
{
  den.aspects.routeros.base = {
    "terragrunt-stacks" =
      { routerosDevice, ... }:
      let
        stack = routerosDevice.aspect.terragruntInputs.base;

        registryUsers = lib.filterAttrs (
          _: u: u.routerosDevices ? ${routerosDevice.name}
        ) den.users.registry;

        routeros_users = {
          # No password_item: op_item_routeros now names whichever fleet
          # user the provider connects as, not admin, so admin's password
          # must stay unmanaged rather than reuse that item.
          admin.disabled = true;
        }
        // lib.mapAttrs (
          username: u:
          let
            devCfg = u.routerosDevices.${routerosDevice.name};
            sshKeys = if devCfg.sshKeys == null then u.sshKeys else devCfg.sshKeys;
          in
          {
            inherit (devCfg) group;
            password_item = "${lib.toUpper routerosDevice.name} - user - ${username}";
          }
          // lib.optionalAttrs (sshKeys != [ ]) { ssh_keys = sshKeys; }
        ) registryUsers;

        # den.groups is global/non-duplicated, but not every device needs
        # every group materialized as a RouterOS resource (e.g. a device
        # with no external-dns user shouldn't get an external-dns group
        # either) — only emit the groups actually referenced on this device.
        referencedGroups = lib.unique (
          lib.mapAttrsToList (_: u: u.routerosDevices.${routerosDevice.name}.group) registryUsers
        );
        routeros_groups = lib.mapAttrs (_: g: { inherit (g) policies; }) (
          lib.filterAttrs (name: _: lib.elem name referencedGroups) den.groups
        );
      in
      {
        stack = "base";
        moduleSource = "ros-base";
        moduleVersion = "2.0.0";
        inherit (stack) dependsOn;
        inputs = stack.inputs // {
          inherit routeros_users routeros_groups;
        };
      };
  };
}
