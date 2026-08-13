# Registers "k8s-manifests" as a den content class. Collected per-cluster
# by modules/den/policies/cluster.nix's cluster-to-nixidy policy.
{
  den.classes.k8s-manifests = {
    description = "Kubernetes manifests collected for nixidy";
  };
}
