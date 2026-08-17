# Shared per-app SopsSecret declaration convention for the sops-operator
# design (modules/kubernetes/sops-operator/default.nix). Unlike the
# Terraform-driven designs on the external-secrets-1password/-openbao
# branches, there's no "shape vs value" split here: a plaintext value is
# read from a LOCAL, gitignored file (secrets/values/**, see .gitignore) at
# Nix-eval time, built straight into the SopsSecret's stringData, and
# immediately re-encrypted by nixidy's own objectTransforms postProcess
# (sops --encrypt) the moment `nix run .#write-manifests` runs — the
# plaintext itself never touches the committed tree, only real ciphertext
# does. A value file that doesn't exist yet renders as an empty string, not
# an eval error, so an app's manifests stay buildable/checkable before a
# human has filled a value in locally.
#
# Rendered as raw YAML text (applications.<name>.yamls), not a
# generators.fromChartCRDModule typed resource: the SopsSecret CRD's schema
# requires a top-level `sops` block (lastmodified/mac, added BY `sops
# --encrypt` itself) that a pre-encryption plaintext document doesn't have
# yet — a typed resource would fail Nix-side schema validation for missing
# a field that's only ever added after the fact.
#
# Leading underscore: import-tree skips this, same convention as
# modules/network/_ros-lib.nix.
{ lib }:
{
  # namespace/name identify the SopsSecret (and its one contained k8s
  # Secret, same name). field = { name, valuePath } — valuePath is relative
  # to secrets/values/.
  mkSopsSecretYaml =
    {
      namespace,
      name,
      fields,
    }:
    let
      stringData = lib.listToAttrs (
        map (
          f:
          let
            path = ../../secrets/values + "/${f.valuePath}";
          in
          {
            inherit (f) name;
            value = if builtins.pathExists path then lib.removeSuffix "\n" (builtins.readFile path) else "";
          }
        ) fields
      );
    in
    builtins.toJSON {
      apiVersion = "addons.projectcapsule.dev/v1alpha1";
      kind = "SopsSecret";
      metadata = { inherit name namespace; };
      spec.secrets = [ { inherit name stringData; } ];
    };
}
