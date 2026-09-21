# Exposes Helm chart derivations built from local pins under ../../charts
# (repo/chart/version/chartHash per charts/<org>/<chart>/default.nix) as a
# flake output, so k8s-manifests aspects can reference `charts.<repo>.<chart>`
# without depending on any of these inputs directly.
{
  inputs,
  config,
  lib,
  withSystem,
  ...
}:
{
  flake-file.inputs = {
    nix-kube-generators.url = "github:farcaller/nix-kube-generators/810dcf792081790648ba9ae705b9a2286115ace8";
    haumea = {
      url = "github:nix-community/haumea/v0.2.2";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Chart derivations no longer come from nixhelm's own index — kept only
    # for its helmupdater CLI (modules/flake/devshell.nix), used to add/bump
    # entries under ../../charts.
    nixhelm = {
      url = "github:farcaller/nixhelm/8a19607cd16231e1f92e10174ff562f9c6d52984";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # nixhelm's own cache — without it, helmupdater's Python venv (built via
  # uv2nix) builds from source on every cold machine, since nothing in it
  # comes from cache.nixos.org. https://github.com/farcaller/nixhelm#using-the-cache
  flake-file.nixConfig = {
    extra-substituters = [ "https://nixhelm.cachix.org" ];
    extra-trusted-public-keys = [
      "nixhelm.cachix.org-1:esqauAsR4opRF0UsGrA6H3gD21OrzMnBBYvJXeddjtY="
    ];
  };

  # Plain repo/chart/version/chartHash data, no fetching — helmupdater
  # reads this via `nix eval .#chartsMetadata.<org>.<chart>` to know what's
  # currently pinned.
  flake.chartsMetadata = inputs.haumea.lib.load {
    src = ../../charts;
    transformer = inputs.haumea.lib.transformers.liftDefault;
  };

  flake.chartsDerivations = lib.genAttrs config.systems (
    system:
    withSystem system (
      { pkgs, ... }:
      let
        kubelib = inputs.nix-kube-generators.lib { inherit pkgs; };
      in
      inputs.haumea.lib.load {
        src = ../../charts;
        loader = _: path: kubelib.downloadHelmChart (import path);
        transformer = inputs.haumea.lib.transformers.liftDefault;
      }
    )
  );
}
