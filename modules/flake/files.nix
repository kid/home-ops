# checks.manifests + apps.write-manifests: diffs/syncs each cluster's built
# nixidy manifest tree (config.flake.nixidyEnvs.<system>.<cluster>, from
# modules/den/policies/cluster.nix's cluster-to-nixidy) against the
# committed `manifests/<rootPath>/` directory — same drift-check-and-sync
# pattern as this repo's own checks.terragrunt/apps.write-terragrunt.
#
# write-manifests runs the real `nixidy switch` CLI (not just a sandboxed
# build+rsync of environmentPackage) so objectTransforms.postProcess rules
# actually run — specifically modules/kubernetes/sops-operator/default.nix's
# sops --encrypt rule for SopsSecret objects. postProcess needs real `sops`
# + network/host access nixidy deliberately keeps outside any Nix build
# sandbox, so it can only run here (human-run, via `nix run`), never inside
# checks.manifests's sandboxed comparison — that check instead excludes
# SopsSecret-*.yaml from its diff (expected to differ: committed = real
# ciphertext, environmentPackage = never-postprocessed plaintext).
{
  inputs,
  lib,
  self,
  ...
}:
{
  perSystem =
    {
      system,
      pkgs,
      config,
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
          inputs.nixidy.packages.${system}.default
          pkgs.nix
          pkgs.sops
        ];
        # NIXIDY_POST_PROCESS_APPROVE=1: skips nixidy's own interactive
        # confirmation prompt before running postProcess commands. The only
        # one that exists is this repo's own `sops --encrypt` rule, not a
        # third-party app's arbitrary command — same trust level already
        # extended to every other write-* command in this repo.
        text = lib.concatStringsSep "\n" (
          lib.mapAttrsToList (name: env: ''
            echo "==> Switching ${name} (writes ${targetDirFor env})..."
            NIXIDY_POST_PROCESS_APPROVE=1 nixidy switch ".#${name}"
          '') envs
        );
      };

      apps.write-manifests = {
        type = "app";
        program = "${config.packages.write-manifests}/bin/write-manifests";
      };
    };
}
