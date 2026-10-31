_: {
  den.aspects.kubernetes.external-dns-cloudflare."terragrunt-stacks" = { cluster, ... }: {
    stack = "external-dns-cloudflare";
    localModule = "external-dns-cloudflare";
    inputs = {
      cluster_name = cluster.name;
      account_id = cluster.cloudflare.accountId;
      cloudflare_zone_id = cluster.cloudflare.zoneId;
    };
  };
}
