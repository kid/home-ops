# Collects den.quirks.firewall-ports onto every cluster, mirroring pipes.nix's cluster-collect-k3s-nodes.
# Only a cluster's own aspects' ports: the predicate keeps every other cluster's out
# (a cluster's own scope is never a collectAll candidate; its own fragments are already there).
# Hosts' fragments carry their `cluster` and are filtered on it, like pipes.nix's
# cluster-collect-k3s-nodes.
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
        (pipe.collectAll ({ host, ... }: host != null))
        (pipe.filter (p: p.cluster or own == own))
      ])
    ];

  den.schema.cluster.includes = [ den.policies.cluster-collect-firewall-ports ];
}
