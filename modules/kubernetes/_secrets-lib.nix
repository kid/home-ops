# Shared per-app SopsSecret shape for the sops-operator design
# (modules/kubernetes/sops-operator/default.nix). Deliberately builds only
# the empty shape — no value, no file read, no Nix-eval-time knowledge of
# secrets/ at all. nixidy's own sandboxed build can't see a secret's real
# value regardless (it only sees git-tracked/staged files, and a decrypted
# scratch copy is neither), so the merge happens for real, after nixidy
# renders this shape: `nix run .#write-manifests` (modules/flake/files.nix)
# locates each rendered SopsSecret-*.yaml by its own metadata.namespace/
# metadata.name, decrypts the matching committed
# secrets/clusters/<cluster>/<namespace>/<name>.sops.json (pure data, no
# k8s shape — {field: value, ...}; grouping fields like username/password
# is just more keys, no extra Nix wiring), splices it into stringData, and
# re-encrypts the whole file in place with sops.
#
# That committed value file is edited directly with sops — `sops -e -i` to
# create it, `sops <file>` to edit later — no custom provisioning tool.
#
# Leading underscore: import-tree skips this, same convention as
# modules/network/_ros-lib.nix.
{
  mkSopsSecretYaml =
    { namespace, name }:
    builtins.toJSON {
      apiVersion = "addons.projectcapsule.dev/v1alpha1";
      kind = "SopsSecret";
      metadata = { inherit name namespace; };
      spec.secrets = [
        {
          inherit name;
          stringData = { };
        }
      ];
    };
}
