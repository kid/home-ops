# Quirk metadata registration. Collected onto the prd cluster by
# modules/den/policies/pipes.nix's cluster-collect-miroir-nodes,
# consumed by modules/den/aspects/kubernetes/miroir/default.nix.
{
  den.quirks.miroir-nodes.description = "miroir storage node info (hostname, block device) for the miroir StorageNode CRD";
}
