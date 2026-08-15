# Shared per-app secret-declaration convention: one spec drives both the
# OpenBao KV secret Terraform creates (modules/flake/openbao-items.nix,
# tf-modules/openbao-items/) and the ExternalSecret k8s manifest that reads
# it (modules/kubernetes/external-secrets/default.nix), so the two can never
# drift out of sync with each other. Leading underscore: import-tree skips
# this, same convention as modules/network/_ros-lib.nix. Needs no outside
# args, so unlike that file this is a plain attrset, not a function.
{
  # spec = { path, fields }
  #   path  -> the OpenBao KV v2 secret's path within the shared "secret"
  #            mount (modules/kubernetes/openbao/default.nix), e.g.
  #            "cert-manager/cloudflare-dns-api-token".
  # field = { name, generate ? false, length ? 32, k8sKey ? name }
  #   generate = true  -> Terraform mints the value itself (random password/
  #                        token), fully automated.
  #   generate = false -> Terraform creates the field empty; a human or
  #                        secretspec fills the real value in afterward.

  mkOpenBaoItem =
    { path, fields }:
    {
      inherit path;
      fields = map (f: {
        inherit (f) name;
        generate = f.generate or false;
        length = f.length or 32;
      }) fields;
    };

  # ESO's OpenBao provider (spec.provider.openBao) uses the classic Vault-
  # style ExternalSecret .data[] shape: remoteRef.key is the KV path, .property
  # is the field name within that path's JSON blob (external-secrets.io's
  # OpenBaoProvider — a dedicated provider, not the 1Password SDK's combined
  # "<item>/<field>" key format).
  mkExternalSecretData =
    { path, fields }:
    map (f: {
      secretKey = f.k8sKey or f.name;
      remoteRef = {
        key = path;
        property = f.name;
      };
    }) fields;
}
