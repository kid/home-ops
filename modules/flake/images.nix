# Container images built by Nix: `perSystem.images.<name>` takes a
# dockerTools.streamLayeredImage. CI (.github/workflows/nix-flake-check.yaml)
# pushes each to `ghcr.io/kid/home-ops-<name>`, tagged with the image's Nix
# hash, so a pushed tag never changes. k8s-manifests aspects get the full
# reference as `images.<name>` (modules/den/policies/cluster.nix).
#
#   nix build .#images.<name>    # the stream script; run it for the tarball
#   nix eval --json .#imageRefs  # <name> -> reference
{ flake-parts-lib, lib, ... }:
{
  options.perSystem = flake-parts-lib.mkPerSystemOption {
    options.images = lib.mkOption {
      type = lib.types.lazyAttrsOf lib.types.package;
      default = { };
      description = "Nix-built container images, pushed by CI and referenced by manifests.";
    };
  };

  config.perSystem =
    { config, ... }:
    {
      legacyPackages = {
        inherit (config) images;
        imageRefs =
          config.images |> lib.mapAttrs (name: image: "ghcr.io/kid/home-ops-${name}:${image.imageTag}");
      };
    };
}
