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
        # One per OIDC client in default.nix's identity_providers.oidc.clients
        # that has a client_secret.path — kept here, not in the module itself,
        # so a new client needs no tf-catalog change.
        extra_secret_names = [
          "argocd-client-secret"
          "kubelogin-client-secret"
          "grafana-client-secret"
        ];
        users.kid = {
          displayname = "Arnaud Rebts";
          email = "arnaud.rebts@gmail.com";
          groups = [ "admins" ];
        };
      };
    };
}
