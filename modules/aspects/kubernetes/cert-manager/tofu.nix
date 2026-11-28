# The Cloudflare DNS-01 API token cert-manager's ClusterIssuer reads from the
# "cloudflare-dns-api-token" 1Password item (see default.nix).
_: {
  den.aspects.kubernetes.cert-manager.tofu =
    { cluster, ... }:
    {
      data.onepassword_vault.home_ops_prd.name = cluster.secrets.onepasswordVault;

      data.cloudflare_account_api_token_permission_groups_list.dns_write = {
        account_id = cluster.cloudflare.accountId;
        name = "DNS%20Write";
      };

      resource.cloudflare_account_token.cert_manager_dns = {
        account_id = cluster.cloudflare.accountId;
        name = "cert-manager-dns01-${cluster.name}";
        policies = [
          {
            effect = "allow";
            permission_groups = [
              { id = "\${data.cloudflare_account_api_token_permission_groups_list.dns_write.result[0].id}"; }
            ];
            resources = builtins.toJSON {
              "com.cloudflare.api.account.zone.${cluster.cloudflare.zoneId}" = "*";
            };
          }
        ];
      };

      resource.onepassword_item.cert_manager_dns_api_token = {
        vault = "\${data.onepassword_vault.home_ops_prd.uuid}";
        title = "cloudflare-dns-api-token";
        category = "secure_note";
        section = [
          {
            label = "credentials";
            field = [
              {
                label = "token";
                type = "CONCEALED";
                value = "\${cloudflare_account_token.cert_manager_dns.value}";
              }
            ];
          }
        ];
      };
    };
}
