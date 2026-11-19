# refresh-nix-hash (run by .renovate/org-inherited-config.json5's
# postUpgradeTasks) and the renovate-operator executor image that carries it.
#
#   nix run .#refresh-nix-hash <file> <dep-name> <new-value>
_: {
  perSystem =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      packages = {
        refresh-nix-hash = pkgs.callPackage ./_refresh-nix-hash.nix { };
      }
      // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        renovate-image = pkgs.callPackage ./_image.nix { };
      };

      apps.refresh-nix-hash = {
        type = "app";
        program = "${config.packages.refresh-nix-hash}/bin/refresh-nix-hash";
      };
    };
}
