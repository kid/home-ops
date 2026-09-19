# Renovate rewrites only the version line of a pin, but every pin here has a
# content hash next to it (a fetchFromGitHub `hash`, a charts/ `chartHash`).
# Left stale, the hash still matches the *old* content, so Nix reuses the old
# fixed-output derivation and the bump silently changes nothing (this is what
# happened to the argocd pin). This app recomputes the hash; .renovaterc.json5
# runs it through postUpgradeTasks right after each bump.
#
#   refresh-nix-hash <file> <dep-name> <new-value>
#
# charts/<org>/<chart>/default.nix is delegated to helmupdater; anything else
# is a fetchFromGitHub pin (dep-name is "owner/repo", new-value is the rev).
_: {
  perSystem =
    {
      config,
      pkgs,
      inputs',
      ...
    }:
    {
      packages.refresh-nix-hash = pkgs.writeShellApplication {
        name = "refresh-nix-hash";
        runtimeInputs = [
          pkgs.gnused
          inputs'.nixhelm.packages.helmupdater
        ];
        text = ''
          if [ "$#" -ne 3 ]; then
            echo "usage: refresh-nix-hash <file> <dep-name> <new-value>" >&2
            exit 1
          fi
          file=$1
          dep_name=$2
          rev=$3

          case "$file" in
            charts/*/*/default.nix)
              pin=''${file#charts/}
              pin=''${pin%/default.nix}
              helmupdater rehash "$pin"
              echo "$file: rehashed $pin"
              exit 0
              ;;
          esac

          owner=''${dep_name%%/*}
          repo=''${dep_name#*/}

          expr="let pkgs = import ${pkgs.path} { }; in pkgs.fetchFromGitHub { owner = \"$owner\"; repo = \"$repo\"; rev = \"$rev\"; hash = pkgs.lib.fakeHash; }"

          if output=$(nix-build --no-out-link -E "$expr" 2>&1); then
            echo "fetchFromGitHub succeeded with a fake hash for $dep_name@$rev — unexpected" >&2
            exit 1
          fi

          new_hash=$(grep -oP 'got:\s+\K\S+' <<< "$output" || true)
          if [ -z "$new_hash" ]; then
            echo "could not determine the correct hash for $dep_name@$rev:" >&2
            echo "$output" >&2
            exit 1
          fi

          sed -i "/rev = \"$rev\";/,/hash = \"/{s|hash = \"[^\"]*\";|hash = \"$new_hash\";|}" "$file"
          echo "$file: $dep_name@$rev -> $new_hash"
        '';
      };

      apps.refresh-nix-hash = {
        type = "app";
        program = "${config.packages.refresh-nix-hash}/bin/refresh-nix-hash";
      };
    };
}
