# Registers "onepassword-items" as a den content class. Collected per-cluster
# by modules/den/policies/cluster.nix's cluster-to-onepassword-items policy,
# into config.flake.onepasswordItems.<cluster.name> — the data
# modules/terragrunt/collect.nix renders into the onepassword-items
# Terraform stack.
{
  den.classes."onepassword-items" = {
    description = "1Password vault items collected for the onepassword-items Terraform stack";
  };
}
