# Collects den.quirks.firewall-ports onto every cluster, mirroring pipes.nix's routeros-device-collect-bgp.
{ den, ... }:
let
  inherit (den.lib.policy) pipe;
in
{
  den.policies.cluster-collect-firewall-ports = _: [
    (pipe.from "firewall-ports" [
      # A bare `_: true` predicate matches nothing — the arg name is the entity-kind filter.
      (pipe.collectAll ({ cluster, ... }: cluster != null))
    ])
  ];

  den.schema.cluster.includes = [ den.policies.cluster-collect-firewall-ports ];
}
