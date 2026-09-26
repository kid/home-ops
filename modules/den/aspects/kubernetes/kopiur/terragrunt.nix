# Provisions the R2 bucket + "kopiur-r2-credentials" 1Password item kopiur's
# ClusterRepository reads (see default.nix).
_: {
  den.aspects.kubernetes.kopiur."terragrunt-stacks" = { cluster, ... }: {
    stack = "kopiur";
    localModule = "kopiur-r2";
    inputs = {
      account_id = cluster.cloudflare.accountId;
      inherit (cluster) environment;
    };
  };
}
