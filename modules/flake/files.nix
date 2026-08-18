# checks.manifests/write-manifests: diff/sync each cluster's built nixidy
# tree against manifests/<rootPath>/.
#
# write-manifests also merges real secret values after the sandboxed build
# (which only ever sees empty stringData): for each SopsSecret-*.yaml it
# decrypts secrets/clusters/<cluster>/<namespace>/<name>.sops.json and
# re-encrypts in place. checks.manifests excludes SopsSecret-*.yaml from
# its diff since that ciphertext is never reproduced by the sandboxed build.
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
