# Registers "k8s-manifests" as a den content class — ported from nixopslab's
# modules/flake/k8s.nix (there also re-declared/merged with a more specific
# description in modules/kubernetes/argocd/default.nix; den classes merge
# like normal options). Collected per-cluster by
# modules/den/policies/cluster.nix's cluster-to-nixidy policy.
{
  den.classes.k8s-manifests = {
    description = "Kubernetes manifests collected for nixidy";
  };
}
