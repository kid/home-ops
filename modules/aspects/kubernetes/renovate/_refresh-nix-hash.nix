# Renovate rewrites only the version line of a pin, but the content hash next
# to it must change too. Left stale, a fetchFromGitHub hash still matches the
# *old* content (its store name is always "source"), so Nix reuses the old
# fixed-output derivation and the bump silently changes nothing.
# .renovate/org-inherited-config.json5 runs this through postUpgradeTasks right
# after each bump, from the root of the repo being updated.
#
#   refresh-nix-hash <file> <dep-name> <new-value>
#
# pkgs/by-name/<name>/package.nix is handed to nix-update, which runs the
# package's updateScript when present (e.g. for multi-platform hashes), or
# refreshes the hashes it knows (src, vendorHash, cargoHash, npmDepsHash...).
# Anything else is a bare fetchFromGitHub pin: dep-name is "owner/repo" and
# new-value the literal `rev`.
{
  writeShellApplication,
  gnused,
  nix-update,
  path,
}:
writeShellApplication {
  name = "refresh-nix-hash";
  runtimeInputs = [
    gnused
    nix-update
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
      pkgs/by-name/*/package.nix)
        attr=''${file#pkgs/by-name/}
        attr=''${attr%/package.nix}
        # nix-update's updateScript runner imports <nixpkgs>, even for flakes.
        NIX_PATH="nixpkgs=${path}''${NIX_PATH:+:$NIX_PATH}" \
          nix-update --flake --use-update-script --version=skip --override-filename "$file" "$attr"
        exit 0
        ;;
    esac

    owner=''${dep_name%%/*}
    repo=''${dep_name#*/}

    expr="let pkgs = import ${path} { }; in pkgs.fetchFromGitHub { owner = \"$owner\"; repo = \"$repo\"; rev = \"$rev\"; hash = pkgs.lib.fakeHash; }"

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

    if ! grep -q "rev = \"$rev\";" "$file"; then
      echo "$file: no literal 'rev = \"$rev\";' to anchor the hash on" >&2
      exit 1
    fi
    sed -i "/rev = \"$rev\";/,/hash = \"/{s|hash = \"[^\"]*\";|hash = \"$new_hash\";|}" "$file"
    echo "$file: $dep_name@$rev -> $new_hash"
  '';
}
