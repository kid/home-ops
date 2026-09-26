# Provisions the RouterOS user/group + "mikrotik-credentials" 1Password item
# external-dns's webhook provider reads (see default.nix).
_: {
  den.aspects.kubernetes.external-dns."terragrunt-stacks" = { cluster, ... }: {
    stack = "external-dns";
    localModule = "external-dns";
    inputs.cluster_name = cluster.name;
  };
}
