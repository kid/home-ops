# Quirk metadata registration. Emitted per host by
# modules/nixos/services/log-shipping.nix, collected onto every cluster by
# modules/den/policies/pipes.nix's cluster-collect-log-shippers, consumed by
# modules/kubernetes/victoria-metrics/vlagent-hosts.nix.
{
  den.quirks.log-shippers.description = "Hosts outside the cluster sending their journal to its vlagent (hostname, address)";
}
