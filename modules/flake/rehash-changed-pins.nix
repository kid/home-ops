# Rehashes every pin bumped in the working tree: charts/<org>/<chart>/default.nix
# (rehash-chart) and the `# renovate: datasource=github-releases` fetchFromGitHub
# pins (refresh-nix-hash) of every changed .nix file. .renovaterc.json5 runs it
# before each write-manifests: Renovate applies a grouped branch's bumps all at
# once, then runs each one's postUpgradeTasks in turn, so a per-pin rehash left
# the later pins' hashes stale when the first write-manifests evaluated them.
#
#   nix run .#rehash-changed-pins
_: {
  perSystem =
    { config, pkgs, ... }:
    {
      packages.rehash-changed-pins = pkgs.writeShellApplication {
        name = "rehash-changed-pins";
        runtimeInputs = [
          pkgs.git
          pkgs.gawk
          config.packages.rehash-chart
          config.packages.refresh-nix-hash
        ];
        text = ''
          git diff --name-only HEAD -- '*.nix' | while IFS= read -r file; do
            case "$file" in
              charts/*/*/default.nix)
                rehash-chart "$file"
                continue
                ;;
            esac
            # `# renovate: datasource=github-releases depName=<owner/repo>`,
            # then the pin's `rev = "<tag>";` line.
            awk '
              /# renovate: datasource=github-releases depName=/ {
                match($0, /depName=[^ ]+/)
                dep = substr($0, RSTART + 8, RLENGTH - 8)
                getline
                if (match($0, /rev = "[^"]+"/)) print dep, substr($0, RSTART + 7, RLENGTH - 8)
              }
            ' "$file" | while read -r dep rev; do
              refresh-nix-hash "$file" "$dep" "$rev"
            done
          done
        '';
      };
    };
}
