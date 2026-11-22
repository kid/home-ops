# Passwords a cluster's apps need generated once and kept across rebuilds,
# contributed by the app aspects that read them. The external-secrets aspect
# renders them all into one Terragrunt stack (modules/kubernetes/external-secrets/
# terragrunt.nix, tf-catalog/modules/generated-secrets): a random_password per
# item, stored in the cluster's 1Password vault as a single-field secure note,
# which the app's ExternalSecret reads back (`cluster.methods.mkGeneratedSecret`).
# Fragment shape, the module's `items` entry plus its key:
# { item; field; length; upper ? true; lower ? true; numeric ? true;
# special ? true; min_upper ? 0; min_lower ? 0; min_numeric ? 0;
# min_special ? 0; override_special ? null; }: `item` the 1Password item
# title and the Kubernetes Secret's name, `field` the item's field label in
# its `credentials` section and the Secret's key, the rest
# random_password's arguments.
{
  den.quirks.generated-secrets.description = "Passwords generated once in Terraform and stored in the cluster's 1Password vault, contributed by the app aspects whose ExternalSecrets read them";
}
