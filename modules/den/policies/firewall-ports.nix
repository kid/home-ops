# Collects den.quirks.firewall-ports onto every cluster, mirroring pipes.nix's routeros-device-collect-bgp.
# Only a cluster's own aspects' ports: the predicate keeps every other cluster's out
# (a cluster's own scope is never a collectAll candidate; its own fragments are already there).
{ den, ... }:
let
  inherit (den.lib.policy) pipe;
in
{
  den.policies.cluster-collect-firewall-ports =
    { cluster, ... }:
    let
      own = cluster.name;
    in
    [
      (pipe.from "firewall-ports" [
        # A bare `_: true` predicate matches nothing — the arg name is the entity-kind filter.
        (pipe.collectAll ({ cluster, ... }: cluster.name == own))
      ])
    ];

  den.schema.cluster.includes = [ den.policies.cluster-collect-firewall-ports ];
}
