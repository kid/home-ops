# The R2 bucket, its access token and the "kopiur-r2-credentials" 1Password
# item kopiur's ClusterRepository reads (see default.nix).
_: {
  den.aspects.kubernetes.kopiur.tofu =
    { cluster, ... }:
    let
      accountId = cluster.cloudflare.accountId;
      bucket = "home-ops-${cluster.environment}-kopiur";
    in
    {
      data.onepassword_vault.home_ops_prd.name = cluster.secrets.onepasswordVault;

      data.cloudflare_account_api_token_permission_groups_list.r2_write = {
        account_id = accountId;
        name = "Workers%20R2%20Storage%20Bucket%20Item%20Write";
      };

      resource.cloudflare_r2_bucket.kopiur = {
        account_id = accountId;
        name = bucket;
      };

      resource.cloudflare_account_token.kopiur_r2 = {
        account_id = accountId;
        name = "kopiur@home-ops/${cluster.environment}";
        policies = [
          {
            effect = "allow";
            permission_groups = [
              { id = "\${data.cloudflare_account_api_token_permission_groups_list.r2_write.result[0].id}"; }
            ];
            resources = builtins.toJSON {
              "com.cloudflare.edge.r2.bucket.${accountId}_default_${bucket}" = "*";
            };
          }
        ];
      };

      resource.random_password.kopiur_repository_password = {
        length = 48;
        special = false;
      };

      # R2's S3 credentials are the token's ID and the SHA-256 of its value.
      resource.onepassword_item.kopiur_r2 = {
        vault = "\${data.onepassword_vault.home_ops_prd.uuid}";
        title = "kopiur-r2-credentials";
        category = "secure_note";
        section = [
          {
            label = "credentials";
            field = [
              {
                label = "access-key-id";
                type = "STRING";
                value = "\${cloudflare_account_token.kopiur_r2.id}";
              }
              {
                label = "secret-access-key";
                type = "CONCEALED";
                value = "\${sha256(cloudflare_account_token.kopiur_r2.value)}";
              }
              {
                label = "repository-password";
                type = "CONCEALED";
                value = "\${random_password.kopiur_repository_password.result}";
              }
            ];
          }
        ];
      };
    };
}
