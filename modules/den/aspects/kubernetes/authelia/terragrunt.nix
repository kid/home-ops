# Kept only so `terragrunt destroy` can still run from tf-stacks/prd/k3s/authelia:
# Authelia is gone from the cluster, but this stack's state still owns its
# 1Password items. Remove this file, its include in modules/den/clusters/prd.nix,
# tf-catalog/modules/authelia and tf-stacks/prd/k3s/authelia once it is destroyed.
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
        # The former OIDC clients' secrets, left as applied so the destroy plan
        # matches the state.
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
