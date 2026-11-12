# Quirk metadata registration. Collected onto the host's own cluster (its
# settings.k3s.clusterName, the fragment's `cluster`) by
# modules/den/policies/pipes.nix's cluster-collect-miroir-nodes,
# consumed by modules/kubernetes/miroir/default.nix.
{
  den.quirks.miroir-nodes.description = "miroir storage node info (hostname) for the miroir StorageNode CRD";
}
