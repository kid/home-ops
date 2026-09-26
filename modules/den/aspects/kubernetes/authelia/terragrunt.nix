# Provisions the "authelia" 1Password vault secrets (OIDC/session/storage
# keys, SMTP password, users database) default.nix's ExternalSecrets read.
# `users` has no existing Nix source of truth (den.users.registry's groups
# are a different, RouterOS/NixOS access-policy axis, not Authelia's OIDC
# groups) and stays a literal attrset.
_: {
  den.aspects.kubernetes.authelia."terragrunt-stacks" =
    { cluster, hcl, ... }:
    {
      stack = "authelia";
      localModule = "authelia";
      inputs = {
        op_vault = cluster.secrets.onepasswordVault;
        url = "https://${cluster.methods.mkAppHostname "auth"}";
        smtp_password = hcl.raw ''get_env("GOOGLE_APP_PASSWORD")'';
        users.kid = {
          displayname = "Arnaud Rebts";
          email = "arnaud.rebts@gmail.com";
          groups = [ "admins" ];
        };
      };
    };
}
