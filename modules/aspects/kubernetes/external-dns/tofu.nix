# The RouterOS user/group and the "mikrotik-credentials" 1Password item
# external-dns's webhook provider reads (see default.nix).
_: {
  den.aspects.kubernetes.external-dns.tofu =
    { cluster, ... }:
    {
      data.onepassword_vault.home_ops.name = "home-ops";
      data.onepassword_vault.home_ops_prd.name = cluster.secrets.onepasswordVault;

      # The routeros provider connects as whichever fleet user op_item_routeros
      # names for rb5009 (see modules/fleet/routeros/rb5009.nix), as the ros-*
      # Terragrunt stacks do.
      data.onepassword_item.routeros_admin = {
        vault = "\${data.onepassword_vault.home_ops.uuid}";
        title = "RB5009 - user - kid";
      };

      provider.routeros.default = {
        hosturl = "https://10.99.0.1";
        username = "\${data.onepassword_item.routeros_admin.username}";
        password = "\${data.onepassword_item.routeros_admin.password}";
        insecure = true;
      };

      resource.random_password.external_dns = {
        length = 32;
        special = false;
      };

      resource.routeros_system_user_group.external_dns = {
        name = "external-dns-${cluster.name}";
        policy = [
          "api"
          "read"
          "rest-api"
          "write"
        ];
      };

      resource.routeros_system_user.external_dns = {
        name = "external-dns-${cluster.name}";
        group = "\${routeros_system_user_group.external_dns.name}";
        password = "\${random_password.external_dns.result}";
      };

      resource.onepassword_item.external_dns_mikrotik_credentials = {
        vault = "\${data.onepassword_vault.home_ops_prd.uuid}";
        title = "mikrotik-credentials";
        category = "secure_note";
        section = [
          {
            label = "credentials";
            field = [
              {
                label = "username";
                type = "STRING";
                value = "\${routeros_system_user.external_dns.name}";
              }
              {
                label = "password";
                type = "CONCEALED";
                value = "\${random_password.external_dns.result}";
              }
            ];
          }
        ];
      };
    };
}
