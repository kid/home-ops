# User entity schema and registry: a standalone registry + access-grant
# pattern, replacing the simpler built-in host.users.<name> inline
# declaration + host-to-users policy (see modules/den/policies/users.nix,
# which excludes host-to-users).
{ lib, den, ... }:
let
  registryUserType = lib.types.submodule (
    { name, config, ... }:
    {
      freeformType = lib.types.attrsOf lib.types.anything;
      imports = [ den.schema.user ];
      config._module.args.user = config;
      options = {
        name = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = "User name (from attrset key)";
        };

        userName = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = "User account name";
        };

        aspect = lib.mkOption {
          type = lib.types.raw;
          default = den.aspects.${name} or { };
          defaultText = "den.aspects.<name>";
          description = "Aspect that configures this user";
        };

        # Access-policy groups, matched against fleet.user-access grants
        # (modules/den/policies/users.nix) — a different axis from NixOS's
        # own extraGroups below.
        groups = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Access-policy groups, matched against fleet.user-access grants";
        };

        sshKeys = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "SSH public keys for this user";
        };

        extraGroups = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "NixOS users.users.<name>.extraGroups on hosts this user is granted onto";
        };

        hashedPassword = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = "!";
          description = "NixOS users.users.<name>.hashedPassword placeholder (real hashes/1Password wiring are a separate task)";
        };

        # RouterOS device membership + per-device data. Not part of the
        # host-side access-grant machinery above — den.users.registry is a
        # flat, non-entity registry (a single producer read directly by
        # modules/den/aspects/routeros/base.nix, not walked via the scope
        # tree the NixOS side's resolve.to/quirks machinery uses).
        # Keyed by den.routerosDevices.<name> name (not den.devices, the
        # unrelated network client-device registry).
        routerosDevices = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                group = lib.mkOption {
                  type = lib.types.str;
                  description = "RouterOS group name on this device";
                };
                sshKeys = lib.mkOption {
                  type = lib.types.nullOr (lib.types.listOf lib.types.str);
                  default = null;
                  description = "null = inherit this user's own sshKeys; [ ] = explicitly no keys";
                };
              };
            }
          );
          default = { };
          description = "RouterOS devices this user has an account on";
        };
      };
    }
  );
in
{
  config.den.schema.user.isEntity = true;
  # den's own built-in batteries (e.g. unfree-predicate-builder) read
  # user.classes unconditionally on every resolved user — we don't rely on
  # class-based content routing ourselves (aspects write directly to
  # nixos.users.users.<name>, see modules/den/aspects/users/), but the
  # option still needs a default so it exists at all.
  config.den.schema.user.classes = lib.mkDefault [ ];

  options.den.users.registry = lib.mkOption {
    type = lib.types.attrsOf registryUserType;
    default = { };
    description = "User registry with extended schema for fleet policy resolution";
  };
}
