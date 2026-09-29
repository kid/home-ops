# Provisions the Cloudflare DNS-Write API token external-dns-cloudflare's
# Deployment reads (see default.nix).
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
