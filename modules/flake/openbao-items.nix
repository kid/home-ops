# Registers "openbao-items" as a den content class. Collected per-cluster
# by modules/den/policies/cluster.nix's cluster-to-openbao-items policy,
# into config.flake.openbaoItems.<cluster.name> — the data
# modules/terragrunt/openbao-items.nix renders into the openbao-items
# Terraform stack.
{
  den.classes."openbao-items" = {
    description = "OpenBao KV secrets collected for the openbao-items Terraform stack";
  };
}
