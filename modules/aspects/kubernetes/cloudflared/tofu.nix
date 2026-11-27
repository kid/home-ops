# The cluster's Cloudflare Tunnel, and the "cloudflared-tunnel-credentials"
# 1Password item holding its token and the API token the tunnel Gateway
# controller manages it with (see default.nix). den.clusters.<name>.cloudflare.tunnelId
# is this stack's cloudflared_tunnel_id output.
_: {
  den.aspects.kubernetes.cloudflared.tofu =
    { cluster, ... }:
    let
      accountId = cluster.cloudflare.accountId;
    in
    {
      data.onepassword_vault.home_ops_prd.name = cluster.secrets.onepasswordVault;

      resource.cloudflare_zero_trust_tunnel_cloudflared.cloudflared = {
        account_id = accountId;
        name = "k8s-${cluster.name}";
        config_src = "cloudflare";
      };

      data.cloudflare_account_api_token_permission_groups_list.account_all.account_id = accountId;

      resource.cloudflare_account_token.cloudflared_tunnel_gateway = {
        account_id = accountId;
        name = "cloudflare-tunnel-gateway-${cluster.name}";
        policies = [
          {
            effect = "allow";
            permission_groups = [
              {
                id = ''''${[for pg in data.cloudflare_account_api_token_permission_groups_list.account_all.result : pg.id if pg.name == "Cloudflare Tunnel Write"][0]}'';
              }
            ];
            resources = builtins.toJSON { "com.cloudflare.api.account.${accountId}" = "*"; };
          }
        ];
      };

      data.cloudflare_zero_trust_tunnel_cloudflared_token.cloudflared = {
        account_id = accountId;
        tunnel_id = "\${cloudflare_zero_trust_tunnel_cloudflared.cloudflared.id}";
      };

      resource.onepassword_item.cloudflared_credentials = {
        vault = "\${data.onepassword_vault.home_ops_prd.uuid}";
        title = "cloudflared-tunnel-credentials";
        category = "secure_note";
        section = [
          {
            label = "credentials";
            field = [
              {
                label = "api-token";
                type = "CONCEALED";
                value = "\${cloudflare_account_token.cloudflared_tunnel_gateway.value}";
              }
              {
                label = "tunnel-token";
                type = "CONCEALED";
                value = "\${data.cloudflare_zero_trust_tunnel_cloudflared_token.cloudflared.token}";
              }
            ];
          }
        ];
      };

      output.cloudflared_tunnel_id.value = "\${cloudflare_zero_trust_tunnel_cloudflared.cloudflared.id}";
    };
}
