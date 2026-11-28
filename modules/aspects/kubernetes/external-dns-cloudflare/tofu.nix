# The Cloudflare API token external-dns-cloudflare reads from the
# "cloudflare-external-dns-token" 1Password item (see default.nix).
_: {
  den.aspects.kubernetes.external-dns-cloudflare.tofu =
    { cluster, ... }:
    {
      data.onepassword_vault.home_ops_prd.name = cluster.secrets.onepasswordVault;

      data.cloudflare_account_api_token_permission_groups_list.dns_write = {
        account_id = cluster.cloudflare.accountId;
        name = "DNS%20Write";
      };

      resource.cloudflare_account_token.external_dns_cloudflare = {
        account_id = cluster.cloudflare.accountId;
        name = "external-dns-cloudflare-${cluster.name}";
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

      resource.onepassword_item.external_dns_cloudflare_token = {
        vault = "\${data.onepassword_vault.home_ops_prd.uuid}";
        title = "cloudflare-external-dns-token";
        category = "secure_note";
        section = [
          {
            label = "credentials";
            field = [
              {
                label = "token";
                type = "CONCEALED";
                value = "\${cloudflare_account_token.external_dns_cloudflare.value}";
              }
            ];
          }
        ];
      };
    };
}
