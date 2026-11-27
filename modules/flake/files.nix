# Syncs each cluster's built nixidy tree into manifests/<rootPath>/: a
# flake-file write hook, so `nix run .#write-flake` writes it, and
# checks.manifests diffs it.
{
  lib,
  self,
  ...
}:
let
  envsFor = system: self.nixidyEnvs.${system} or { };

  targetDirFor = env: lib.strings.unsafeDiscardStringContext env.config.nixidy.target.rootPath;
in
{
  flake-file.write-hooks = [
    {
      index = 110;
      program =
        pkgs:
        pkgs.writeShellApplication {
          name = "write-manifests";
          runtimeInputs = [ pkgs.rsync ];
          text =
            envsFor pkgs.stdenv.hostPlatform.system
            |> lib.mapAttrsToList (
              name: env: ''
                echo "==> Writing ${name} manifests to ${targetDirFor env}..."
                mkdir -p "${targetDirFor env}"
                rsync -rlL --checksum --delete --chmod=Du+w,Fu+w "${env.environmentPackage}/" "${targetDirFor env}/"
              ''
            )
            |> lib.concatStrings;
        };
    }
  ];

  perSystem =
    { pkgs, system, ... }:
    {
      checks.manifests =
        pkgs.runCommandLocal "manifests-check" { nativeBuildInputs = [ pkgs.diffutils ]; }
          (
            (
              envsFor system
              |> lib.mapAttrsToList (
                _: env: ''
                  if ! diff -rq "${self}/${targetDirFor env}" "${env.environmentPackage}"; then
                    echo "${targetDirFor env} is stale — run: nix run .#write-flake" >&2
                    exit 1
                  fi
                ''
              )
              |> lib.concatStringsSep "\n"
            )
            + "\ntouch $out"
          );
    };
}
