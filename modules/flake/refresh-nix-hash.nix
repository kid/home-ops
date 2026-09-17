# Renovate's custom regex manager (.renovaterc.json5) can bump a `rev`
# pinned via a `# renovate:` comment, but it only rewrites that one line —
# it has no way to recompute the paired `hash` a fetchFromGitHub call
# needs next to it. Left stale, the hash still matches the *old* content,
# so Nix reuses the old fixed-output derivation and the rev bump silently
# produces no manifest changes at all (this is what happened to the
# argocd pin). This app recomputes the hash and is wired into
# postUpgradeTasks so Renovate runs it right after each rev bump.
_: {
  perSystem =
    { config, pkgs, ... }:
    {
      packages.refresh-nix-hash = pkgs.writeShellApplication {
        name = "refresh-nix-hash";
        runtimeInputs = [ pkgs.gnused ];
        text = ''
          if [ "$#" -ne 3 ]; then
            echo "usage: refresh-nix-hash <file> <owner/repo> <rev>" >&2
            exit 1
          fi
          file=$1
          dep_name=$2
          rev=$3
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
