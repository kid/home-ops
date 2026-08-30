# Cluster-level BGP instance parameters, contributed by a cluster's own
# aspect (den.aspects.<cluster>.bgp, e.g. modules/den/clusters.nix) and
# collected onto every RouterOS device (modules/den/policies/pipes.nix's
# routeros-device-collect-bgp). Fragment shape: { name; localAsn; peers;
# holdTimeSeconds; keepAliveTimeSeconds; } — `peers` is
# den.clusters.<name>.bgp.peers verbatim; modules/den/aspects/routeros/
# ros-bgp.nix (the only current consumer) matches `peers` entries against
# its own routerosDevice.name.
{
  den.quirks.bgp.description = "Cluster-level BGP instance parameters (name, local ASN, remote router peers, session timers)";
}
