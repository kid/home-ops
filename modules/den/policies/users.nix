# User access grants + resolution policy.
#
# Ported from den's own official templates/fleet-demo/modules/policies/fleet.nix
# (github:denful/den) — resolves den.users.registry entries onto hosts whose
# granted access-policy groups (fleet.user-access.by-host) intersect the
# user's own `groups`. Replaces den's built-in host-to-users policy, same as
# the reference template does (host.users.<name> inline declarations don't
# scale to a real fleet the way a standalone registry + grants does).
#
# by-environment grants (the other half of the reference template) are
# intentionally not ported yet — this repo's hosts don't carry an
# `environment` field, and there's only one host today. Add
# fleet.user-access.by-environment the same way once that's needed.
{
  lib,
  den,
  config,
  ...
}:
let
  inherit (den.lib.policy) resolve;

  registry = config.den.users.registry;
  accessByHost = config.fleet.user-access.by-host;

  matchRegistryUsers =
    grantedGroups:
    lib.filter (name: builtins.any (g: lib.elem g grantedGroups) registry.${name}.groups) (
      builtins.attrNames registry
    );
in
{
  options.fleet.user-access.by-host = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options.groups = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Access-policy groups granted onto this host";
        };
      }
    );
    default = { };
    description = "Grant user access-policy groups onto a specific host";
  };

  config.den.policies.host-users =
    { host, ... }:
    map (name: resolve.to "user" { user = registry.${name}; }) (
      matchRegistryUsers (accessByHost.${host.name}.groups or [ ])
    );

  config.den.schema.host.includes = [ den.policies.host-users ];
  config.den.schema.host.excludes = [ den.policies.host-to-users ];

  # Content aspects need { host, user } context, which only exists at the
  # resolved user child-scope — not the host's own scope. Wiring them here
  # (schema-level, applies to every resolved user regardless of which host
  # resolved it) rather than into any one host's own includes list, mirrors
  # how modules/terragrunt/collect.nix wires den.schema.routerosDevice.includes.
  config.den.schema.user.includes = [
    den.aspects.define-user
    den.aspects.ssh-keys
  ];
}
