# checks.manifests + apps.write-manifests: diffs/syncs each cluster's built
# nixidy manifest tree (config.flake.nixidyEnvs.<system>.<cluster>, from
# modules/den/policies/cluster.nix's cluster-to-nixidy) against the
# committed `manifests/<rootPath>/` directory — same drift-check-and-sync
# pattern as this repo's own checks.terragrunt/apps.write-terragrunt.
{ lib, self, ... }:
{
  perSystem =
    { system, pkgs, ... }:
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
                if ! diff -rq "${self}/${targetDirFor env}" "${env.environmentPackage}"; then
                  echo "${targetDirFor env} is stale — run: nix run .#write-manifests" >&2
                  exit 1
                fi
              '') envs
            )
            + "\ntouch $out"
          );

      apps.write-manifests = {
        type = "app";
        program = "${
          pkgs.writeShellApplication {
            name = "write-manifests";
            runtimeInputs = [ pkgs.rsync ];
            text = lib.concatStringsSep "\n" (
              lib.mapAttrsToList (name: env: ''
                echo "==> Writing ${name} manifests to ${targetDirFor env}..."
                mkdir -p "${targetDirFor env}"
                rsync -rlL --checksum --delete --chmod=Du+w,Fu+w "${env.environmentPackage}/" "${targetDirFor env}/"
              '') envs
            );
          }
        }/bin/write-manifests";
      };
    };
}
