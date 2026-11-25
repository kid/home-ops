# refresh-nix-hash (run by .renovate/org-inherited-config.json5's
# postUpgradeTasks) and the renovate-operator executor image that carries it.
#
#   nix run .#refresh-nix-hash <file> <dep-name> <new-value>
_: {
  perSystem =
    { pkgs, ... }:
    {
      packages.refresh-nix-hash = pkgs.callPackage ./_refresh-nix-hash.nix { };
      images.renovate = pkgs.callPackage ./_image.nix { };
    };
}
