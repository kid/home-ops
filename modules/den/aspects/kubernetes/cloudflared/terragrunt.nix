# Provisions the Cloudflare Tunnel and its credentials cloudflared/default.nix's
# controller relies on. DNS is external-dns-cloudflare's own terragrunt stack.
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
