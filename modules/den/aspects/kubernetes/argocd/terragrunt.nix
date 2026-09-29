# Provisions ArgoCD's GitHub webhook: the shared secret (1Password) and the
# actual webhook registration on the repo argocd/default.nix's ExternalSecret
# and public HTTPRoute expect it to reach.
_: {
  den.aspects.kubernetes.argocd."terragrunt-stacks" =
    { cluster, ... }:
    let
      # cluster.nixidy.repository is already the one source of truth for
      # which repo ArgoCD syncs from — parse owner/repo out of it instead of
      # adding a second, possibly-drifting literal.
      match = builtins.match "https://github\\.com/([^/]+)/([^.]+)\\.git" cluster.nixidy.repository;
    in
    {
      stack = "argocd";
      localModule = "argocd";
      inputs = {
        cluster_name = cluster.name;
        github_owner = builtins.elemAt match 0;
        github_repo = builtins.elemAt match 1;
        webhook_hostname = cluster.methods.mkAppHostname "argo-webhook";
      };
    };
}
