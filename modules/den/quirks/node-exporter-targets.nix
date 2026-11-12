# Quirk metadata registration. Emitted per host by
# modules/nixos/services/node-exporter.nix, collected onto every cluster by
# modules/den/policies/pipes.nix's cluster-collect-node-exporter-targets,
# consumed by modules/kubernetes/victoria-metrics/default.nix.
{
  den.quirks.node-exporter-targets.description = "Hosts outside the cluster running node-exporter (hostname, address) for vmagent to scrape";
}
