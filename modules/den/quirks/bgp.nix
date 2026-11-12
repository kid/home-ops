# Cluster-level BGP instance parameters, contributed by every cluster that
# includes den.aspects.kubernetes.cilium-bgp (modules/kubernetes/cilium/
# bgp.nix) and collected onto every RouterOS device (modules/den/policies/
# pipes.nix's routeros-device-collect-bgp). Fragment shape: { name; localAsn;
# peers; holdTimeSeconds; keepAliveTimeSeconds; stack; } — `peers` is
# den.clusters.<name>.bgp.peers verbatim and `stack` its bgp.routerosStack;
# modules/routeros/bgp.nix (the only current consumer) matches `peers`
# entries against its own routerosDevice.name and renders one stack each.
{
  den.quirks.bgp.description = "Cluster-level BGP instance parameters (name, local ASN, remote router peers, session timers, RouterOS stack name)";
}
