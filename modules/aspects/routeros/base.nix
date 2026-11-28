# A RouterOS device's base configuration (interfaces, VLANs, addresses, DHCP,
# users): the catalog's ros-base module, called with the device's
# routerosInputs.base, precomputed on its own self-aspect (see
# modules/fleet/routeros/rb5009.nix) since they need cidrLib, which den's
# aspect content functions can't see.
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
let
  inherit (import ./_lib.nix { inherit lib; }) catalogModule;
in
{
  den.aspects.routeros.base = {
    tofu =
      { routerosDevice, ... }:
      let
        inherit (routerosDevice.aspect.routerosInputs.base) inputs;

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
        # true for the first apply against a factory-reset device: the
        # module then connects as admin with no password over plain HTTP
        # (`just tofu routeros-<device> apply -var bootstrap=true -target=module.base`).
        variable.bootstrap = {
          type = "bool";
          default = false;
        };

        # The device's built-in admin user (routeros_users.admin above)
        # already exists; ros-base can't import it itself, as OpenTofu only
        # allows import blocks in a root module. A no-op once it's in state.
        import = [
          {
            to = ''module.base.routeros_system_user.users["admin"]'';
            id = "name=admin";
          }
        ];

        module.base =
          catalogModule {
            name = "ros-base";
            version = "3.0.0";
            variables = [
              "bridge_comment"
              "bridge_mtu"
              "bridge_name"
              "certificate_alt_names"
              "certificate_country"
              "certificate_locality"
              "certificate_organization"
              "certificate_unit"
              "dhcp_clients"
              "dhcp_servers"
              "dhcp_static_leases"
              "ethernet_interfaces"
              "hostname"
              "ip_addresses"
              "mgmt_interface_list"
              "ntp_server_enabled"
              "ntp_servers"
              "op_item_routeros"
              "op_vault"
              "routeros_endpoint"
              "routeros_groups"
              "routeros_insecure"
              "routeros_users"
              "timezone"
              "vlans"
            ];
            inputs = inputs // {
              inherit routeros_users routeros_groups;
            };
          }
          // {
            bootstrap = "\${var.bootstrap}";
          };
      };
  };
}
