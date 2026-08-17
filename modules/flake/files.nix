# checks.manifests + apps.write-manifests: diffs/syncs each cluster's built
# nixidy manifest tree (config.flake.nixidyEnvs.<system>.<cluster>, from
# modules/den/policies/cluster.nix's cluster-to-nixidy) against the
# committed `manifests/<rootPath>/` directory — same drift-check-and-sync
# pattern as this repo's own checks.terragrunt/apps.write-terragrunt.
#
# write-manifests builds+rsyncs each env's sandboxed environmentPackage
# (SopsSecret objects render with an empty stringData — nixidy's build
# only sees git-tracked/staged files, never a real secret value), then
# merges in real values for real: for each rendered SopsSecret-*.yaml, it
# looks up secrets/clusters/<cluster>/<namespace>/<name>.sops.json (see
# modules/kubernetes/_secrets-lib.nix) by that file's own metadata, decrypts
# it, splices the result into .spec.secrets[0].stringData, and re-encrypts
# the whole file in place with sops. checks.manifests's sandboxed
# comparison excludes SopsSecret-*.yaml from its diff (expected to differ:
# committed = real ciphertext, environmentPackage = empty-stringData
# plaintext).
{
  lib,
  self,
  ...
}:
{
  perSystem =
    {
      pkgs,
      config,
      system,
      ...
    }:
    let
      envs = self.nixidyEnvs.${system} or { };

      targetDirFor = env: lib.strings.unsafeDiscardStringContext env.config.nixidy.target.rootPath;
    in
    {
      checks.manifests =
        pkgs.runCommandLocal "manifests-check" { nativeBuildInputs = [ pkgs.diffutils ]; }
          (
            lib.concatStringsSep "\n" (
              lib.mapAttrsToList (_: env: ''
                if ! diff -rq --exclude='SopsSecret-*.yaml' "${self}/${targetDirFor env}" "${env.environmentPackage}"; then
                  echo "${targetDirFor env} is stale — run: nix run .#write-manifests" >&2
                  exit 1
                fi
              '') envs
            )
            + "\ntouch $out"
          );

      packages.write-manifests = pkgs.writeShellApplication {
        name = "write-manifests";
        runtimeInputs = [
          pkgs.rsync
          pkgs.sops
          pkgs.yq
          pkgs.findutils
        ];
        text = lib.concatStringsSep "\n" (
          lib.mapAttrsToList (name: env: ''
            echo "==> Writing ${name} manifests to ${targetDirFor env}..."
            mkdir -p "${targetDirFor env}"
            rsync -rlL --checksum --delete --chmod=Du+w,Fu+w "${env.environmentPackage}/" "${targetDirFor env}/"

            echo "==> Encrypting SopsSecret values for ${name}..."
            while IFS= read -r -d "" f; do
              namespace=$(yq -r '.metadata.namespace' "$f")
              secretName=$(yq -r '.metadata.name' "$f")
              valueFile="secrets/clusters/${name}/$namespace/$secretName.sops.json"
              if [ -f "$valueFile" ]; then
                value=$(sops --decrypt --input-type json --output-type json "$valueFile")
                # shellcheck disable=SC2016 # $v is a jq variable, not a shell one
                yq -y --argjson v "$value" '.spec.secrets[0].stringData = $v' "$f" > "$f.tmp"
                mv "$f.tmp" "$f"
              fi
              sops --encrypt --input-type yaml --output-type yaml -i "$f"
            done < <(find "${targetDirFor env}" -name 'SopsSecret-*.yaml' -print0)
          '') envs
        );
      };

      apps.write-manifests = {
        type = "app";
        program = "${config.packages.write-manifests}/bin/write-manifests";
      };
    };
}
