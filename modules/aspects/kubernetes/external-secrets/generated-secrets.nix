# Passwords the cluster's apps generate once and keep (API keys, MQTT
# logins, cookie keys), collected from their aspects' generated-secrets quirk
# (modules/den/quirks/generated-secrets.nix) into the cluster's tofu stack:
# tofu generates each one into a 1Password item, so a rebuilt cluster reads
# back the same values its apps (and their kopiur-restored settings) already
# hold. Rendered here rather than by each app: the same shape for every item;
# the item's spec still lives with the app that reads it.
{ lib, ... }:
{
  den.aspects.kubernetes.external-secrets.tofu =
    { cluster, generated-secrets, ... }:
    let
      duplicates =
        generated-secrets
        |> map (s: s.item)
        |> lib.groupBy (i: i)
        |> lib.filterAttrs (_: is: builtins.length is > 1)
        |> builtins.attrNames;

      perItem =
        f: generated-secrets |> map (s: lib.nameValuePair "generated_${s.item}" (f s)) |> lib.listToAttrs;
    in
    if duplicates != [ ] then
      throw "generated-secrets: more than one app aspect emits ${lib.concatStringsSep ", " duplicates}"
    else
      lib.optionalAttrs (generated-secrets != [ ]) {
        data.onepassword_vault.home_ops_prd.name = cluster.secrets.onepasswordVault;

        resource.random_password = perItem (
          s:
          removeAttrs s [
            "item"
            "field"
          ]
          |> lib.filterAttrs (_: v: v != null)
          |> lib.mergeAttrs {
            # The apps keep copies of these values in their own settings, so
            # the arguments only shape a new password: changing one never
            # regenerates it. This also keeps a password adopted with
            # `tofu import` (by value), which records every argument at
            # random_password's defaults, from being replaced. Rotate one
            # deliberately with `apply -replace`.
            lifecycle.ignore_changes = [
              "length"
              "upper"
              "lower"
              "numeric"
              "special"
              "min_upper"
              "min_lower"
              "min_numeric"
              "min_special"
              "override_special"
            ];
          }
        );

        resource.onepassword_item = perItem (s: {
          vault = "\${data.onepassword_vault.home_ops_prd.uuid}";
          title = s.item;
          category = "secure_note";
          section = [
            {
              label = "credentials";
              field = [
                {
                  label = s.field;
                  type = "CONCEALED";
                  value = "\${random_password.generated_${s.item}.result}";
                }
              ];
            }
          ];
        });
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
