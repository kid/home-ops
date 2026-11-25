# Provisions the Cloudflare DNS-01 API token cert-manager's ClusterIssuer
# reads from the "cloudflare-dns-api-token" 1Password item (see default.nix).
_: {
  den.aspects.kubernetes.cert-manager."terragrunt-stacks" = { cluster, ... }: {
    stack = "cert-manager";
    localModule = "cert-manager";
    inputs = {
      cluster_name = cluster.name;
      account_id = cluster.cloudflare.accountId;
      cloudflare_zone_id = cluster.cloudflare.zoneId;
    };
  };
}
