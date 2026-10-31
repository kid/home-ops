# User entity schema and registry (den's "Access Control & Environments"
# guide): an identity plus the den.accessGroups it is directly in, replacing
# the built-in host.users.<name> inline declaration + host-to-users policy.
# Which hosts and cluster Kanidms a user reaches is derived from login gates
# in modules/den/policies/users.nix.
{ lib, den, ... }:
let
  # Built from the user kind itself, so den.schema.user.imports apply to
  # registry entries too.
  registryUserType = den.lib.schema.mkInstanceType {
    strict = den.schema.user.isStrict;
    extraModules = [
      (
        { name, config, ... }:
        {
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

            # Groups this user is directly in; membership of every group whose
            # `members` lists one of them follows (modules/den/policies/users.nix).
            groups = lib.mkOption {
              type = lib.types.listOf (lib.types.enum (builtins.attrNames den.accessGroups));
              default = [ ];
              description = "den.accessGroups this user is directly in";
            };

            sshKeys = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "SSH public keys for this user";
            };

            hashedPassword = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = "!";
              description = "NixOS users.users.<name>.hashedPassword placeholder (real hashes/1Password wiring are a separate task)";
            };

            displayName = lib.mkOption {
              type = lib.types.str;
              default = name;
              description = "Full name (Kanidm displayname)";
            };

            mail = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Email addresses, primary first (Kanidm mail)";
            };
          };
        }
      )
    ];
  } den.schema.user;
in
{
  config.den.schema.user.isEntity = true;
  # den's own built-in batteries (e.g. unfree-predicate-builder) read
  # user.classes unconditionally on every resolved user — we don't rely on
  # class-based content routing ourselves (aspects write directly to
  # nixos.users.users.<name>, see modules/nixos/users/), but the
  # option still needs a default so it exists at all.
  config.den.schema.user.classes = lib.mkDefault [ ];

  options.den.users.registry = lib.mkOption {
    type = lib.types.attrsOf registryUserType;
    default = { };
    description = "User registry with extended schema for fleet policy resolution";
  };
}
