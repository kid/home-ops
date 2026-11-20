# Passwords the cluster's apps generate once and keep (API keys, MQTT
# logins, cookie keys), collected from their aspects' generated-secrets quirk
# (modules/den/quirks/generated-secrets.nix) into one Terragrunt stack,
# tf-catalog/modules/generated-secrets: Terraform generates each one into a
# 1Password item, so a rebuilt cluster reads back the same values its apps
# (and their kopiur-restored settings) already hold. One stack rather than
# one per app: a single state and a single apply for every such item, the
# same shape for each; the item's spec still lives with the app that reads it.
{ lib, ... }:
{
  den.aspects.kubernetes.external-secrets."terragrunt-stacks" =
    { cluster, generated-secrets, ... }:
    let
      duplicates =
        generated-secrets
        |> map (s: s.item)
        |> lib.groupBy (i: i)
        |> lib.filterAttrs (_: is: builtins.length is > 1)
        |> builtins.attrNames;
    in
    if duplicates != [ ] then
      throw "generated-secrets: more than one app aspect emits ${lib.concatStringsSep ", " duplicates}"
    else
      {
        stacks = lib.optional (generated-secrets != [ ]) {
          stack = "generated-secrets";
          localModule = "generated-secrets";
          inputs = {
            vault = cluster.secrets.onepasswordVault;
            items =
              generated-secrets
              |> map (s: lib.nameValuePair s.item (removeAttrs s [ "item" ]))
              |> lib.listToAttrs;
          };
        };
      };

  # The ExternalSecret spec reading a generated-secrets fragment back from
  # its item, into the Secret named after the item, under the field's name.
  # The default hourly refresh, like the other 1Password-backed
  # ExternalSecrets: the onepassword store's cache serves most of them.
  den.clusterMethods.mkGeneratedSecret =
    _:
    { item, field, ... }:
    {
      secretStoreRef = {
        name = "onepassword";
        kind = "ClusterSecretStore";
      };
      target.name = item;
      data = [
        {
          secretKey = field;
          remoteRef.key = "${item}/credentials/${field}";
        }
      ];
    };
}
