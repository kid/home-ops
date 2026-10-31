# Access-control resolution (den's "Access Control & Environments" guide,
# https://den.denful.dev/guides/acl-environments/). Three facts, each stated
# once: the den.accessGroups graph, the groups each den.users.registry entry
# is directly in, and the login gates (`system-access-groups`) of each
# environment, host and cluster. A user resolves onto a host iff the closure
# of its groups meets the host's gates plus its environment's; the cluster
# Kanidm (modules/kubernetes/kanidm/default.nix) admits persons
# the same way against the cluster's gates. Replaces den's built-in
# host-to-users policy.
{
  lib,
  den,
  config,
  ...
}:
let
  inherit (den.lib.policy) resolve;
  inherit (config.den) accessGroups environments;

  # Every group a user is in: its direct groups, plus every group listing one
  # of those in `members`, transitively.
  closure =
    direct:
    map (g: g.key) (
      builtins.genericClosure {
        startSet = map (key: { inherit key; }) direct;
        operator =
          { key }:
          lib.mapAttrsToList (name: _: { key = name; }) (
            lib.filterAttrs (_: g: lib.elem key g.members) accessGroups
          );
      }
    );

  acl = {
    inherit closure;
    labelled = label: groups: lib.filter (g: lib.elem label accessGroups.${g}.labels) groups;
    admits = gates: user: lib.any (g: lib.elem g gates) (closure user.groups);
    # An environment's gates plus a host's or cluster's own.
    gatesFor =
      target: environments.${target.environment}.system-access-groups ++ target.system-access-groups;
  };
in
{
  config._module.args.acl = acl;

  config.den.policies.acl-users =
    { host, environment, ... }:
    let
      # den's host merge doesn't apply the option's enum check to list
      # elements, so an undefined group is rejected here instead.
      unknown = lib.subtractLists (builtins.attrNames accessGroups) host.system-access-groups;
      gates =
        if unknown == [ ] then
          environment.system-access-groups ++ host.system-access-groups
        else
          throw "den.hosts.${host.system}.${host.name}.system-access-groups: undefined den.accessGroups ${lib.concatStringsSep ", " unknown}";
    in
    map (user: resolve.to "user" { inherit user; }) (
      lib.filter (acl.admits gates) (builtins.attrValues config.den.users.registry)
    );

  config.den.schema.host.includes = [ den.policies.acl-users ];
  config.den.schema.host.excludes = [ den.policies.host-to-users ];

  # Content aspects need { host, user } context, which only exists at the
  # resolved user child-scope — not the host's own scope. Wiring them here
  # (schema-level, applies to every resolved user regardless of which host
  # resolved it) rather than into any one host's own includes list, mirrors
  # how modules/den/batteries/terragrunt/terragrunt-stacks.nix wires den.schema.routerosDevice.includes.
  config.den.schema.user.includes = [
    den.aspects.define-user
    den.aspects.ssh-keys
  ];
}
