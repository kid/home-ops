# Provisions the Cloudflare Tunnel, its credentials, and the one-time public
# wildcard DNS record cloudflared/default.nix's controller relies on.
_: {
  den.aspects.kubernetes.cloudflared."terragrunt-stacks" = { cluster, ... }: {
    stack = "cloudflared";
    localModule = "cloudflared";
    inputs = {
      cluster_name = cluster.name;
      account_id = cluster.cloudflare.accountId;
      cloudflare_zone_id = cluster.cloudflare.zoneId;
    };
  };
}
