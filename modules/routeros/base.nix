# Shared "base" RouterOS stack aspect — thin: the actual per-device inputs
# (ethernet_interfaces, ip_addresses, dhcp_servers, vlans, …) live on the
# device's own self-aspect (den.aspects.<routerosDevice>.terragruntInputs.base,
# see modules/routerosDevices/rb5009.nix), precomputed there because
# cidrhost()-style arithmetic needs modules/den/batteries/terragrunt/lib.nix's cidrLib, which
# den's aspect content functions can't see (only entity-kind scope bindings
# like `routerosDevice` are — see modules/den/batteries/terragrunt/terragrunt-stacks.nix).
#
# routeros_users/routeros_groups are merged in here instead, derived from
# the access-control model (modules/den/policies/users.nix): every registry
# user the device's gates (its environment's plus its own
# system-access-groups) admit gets an account, in the one `routeros`-labelled
# group of its closure; custom group policies come from den.routerosGroups.
{
  acl,
  den,
  lib,
  ...
}:
{
  den.aspects.routeros.base = {
    "terragrunt-stacks" =
      { routerosDevice, ... }:
      let
        stack = routerosDevice.aspect.terragruntInputs.base;

        groupOf =
          username: u:
          let
            groups = acl.labelled "routeros" (acl.closure u.groups);
          in
          if lib.length groups == 1 then
            lib.head groups
          else
            throw "den.users.registry.${username}: admitted to RouterOS device ${routerosDevice.name}, so it needs exactly one routeros-labelled den.accessGroups group, has ${
              if groups == [ ] then "none" else lib.concatStringsSep ", " groups
            }";

        registryUsers =
          den.users.registry
          |> lib.filterAttrs (_: acl.admits (acl.gatesFor routerosDevice))
          |> lib.mapAttrs (username: u: u // { routerosGroup = groupOf username u; });

        routeros_users = {
          # No password_item: op_item_routeros now names whichever fleet
          # user the provider connects as, not admin, so admin's password
          # must stay unmanaged rather than reuse that item.
          admin.disabled = true;
        }
        // lib.mapAttrs (
          username: u:
          {
            group = u.routerosGroup;
            password_item = "${lib.toUpper routerosDevice.name} - user - ${username}";
          }
          // lib.optionalAttrs (u.sshKeys != [ ]) { ssh_keys = u.sshKeys; }
        ) registryUsers;

        # Only the custom groups some user on this device is in: built-in
        # groups have no den.routerosGroups entry, and a device with no user
        # in a group shouldn't get that group either.
        referencedGroups = registryUsers |> lib.mapAttrsToList (_: u: u.routerosGroup) |> lib.unique;
        routeros_groups =
          den.routerosGroups
          |> lib.filterAttrs (name: _: lib.elem name referencedGroups)
          |> lib.mapAttrs (_: g: { inherit (g) policies; });
      in
      {
        stack = "base";
        moduleSource = "ros-base";
        moduleVersion = "2.2.0";
        inherit (stack) dependsOn;
        inputs = stack.inputs // {
          inherit routeros_users routeros_groups;
        };
      };
  };
}
