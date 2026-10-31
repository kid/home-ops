# Access-control group graph (den's "Access Control & Environments" guide,
# https://den.denful.dev/guides/acl-environments/) — data-only, no isEntity.
# A group's `members` are other groups whose members inherit it; `labels`
# say which consumers read it: `posix` (a Unix group on every host the user
# logs into), `oauth-grant` (a Kanidm group on every cluster), `mfa` (Kanidm
# requires MFA from its members), `routeros` (the RouterOS group of a user
# on every RouterOS device it logs into; exactly one per user). Resolution
# lives in modules/den/policies/users.nix.
{ lib, config, ... }:
let
  groupNames = lib.mkOption {
    type = lib.types.listOf (lib.types.enum (builtins.attrNames config.den.accessGroups));
    default = [ ];
  };
in
{
  options.den.accessGroups = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          description = lib.mkOption {
            type = lib.types.str;
            default = "";
          };
          labels = lib.mkOption {
            type = lib.types.listOf (
              lib.types.enum [
                "posix"
                "oauth-grant"
                "mfa"
                "routeros"
              ]
            );
            default = [ ];
            description = "Consumers of this group";
          };
          members = groupNames // {
            description = "Groups whose members are also members of this one";
          };
        };
      }
    );
    default = { };
    description = "Access-control group graph";
  };
}
