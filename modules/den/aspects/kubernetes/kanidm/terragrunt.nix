# Puts the Gmail app password of Kanidm's mail sender in 1Password, for
# default.nix's kanidm-smtp ExternalSecret.
_: {
  den.aspects.kubernetes.kanidm."terragrunt-stacks" =
    { cluster, hcl, ... }:
    {
      stack = "kanidm";
      localModule = "kanidm";
      inputs = {
        op_vault = cluster.secrets.onepasswordVault;
        smtp_password = hcl.raw ''get_env("GOOGLE_APP_PASSWORD")'';
      };
    };
}
