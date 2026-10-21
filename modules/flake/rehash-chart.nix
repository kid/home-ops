# Renovate rewrites only the `version` of a charts/<org>/<chart>/default.nix
# pin, never its `chartHash`. Left stale, the hash still matches the *old*
# chart. .renovaterc.json5 runs this through postUpgradeTasks right after each
# bump; other Nix pins are rehashed by kid/renovate-config's refresh-nix-hash.
#
#   rehash-chart charts/<org>/<chart>/default.nix
_: {
  perSystem =
    {
      config,
      pkgs,
      inputs',
      ...
    }:
    {
      packages.rehash-chart = pkgs.writeShellApplication {
        name = "rehash-chart";
        runtimeInputs = [ inputs'.nixhelm.packages.helmupdater ];
        text = ''
          if [ "$#" -ne 1 ]; then
            echo "usage: rehash-chart charts/<org>/<chart>/default.nix" >&2
            exit 1
          fi
          file=$1

          case "$file" in
            charts/*/*/default.nix) ;;
            *)
              echo "rehash-chart: not a charts/<org>/<chart>/default.nix pin: $file" >&2
              exit 1
              ;;
          esac

          pin=''${file#charts/}
          pin=''${pin%/default.nix}
          helmupdater rehash "$pin"
          echo "$file: rehashed $pin"
        '';
      };

      apps.rehash-chart = {
        type = "app";
        program = "${config.packages.rehash-chart}/bin/rehash-chart";
      };
    };
}
