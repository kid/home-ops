_: {
  den.aspects.kubernetes.argocd."terragrunt-stacks" =
    { cluster, ... }:
    let
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
