_: {
  den.aspects.kubernetes.cloudflared."terragrunt-stacks" = { cluster, ... }: {
    stack = "cloudflared";
    localModule = "cloudflared";
    inputs = {
      cluster_name = cluster.name;
      account_id = cluster.cloudflare.accountId;
    };
  };
}
