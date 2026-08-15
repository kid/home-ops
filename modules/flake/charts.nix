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
    nix-kube-generators.url = "github:farcaller/nix-kube-generators";
    haumea = {
      url = "github:nix-community/haumea/v0.2.2";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Chart derivations no longer come from nixhelm's own index — kept only
    # for its helmupdater CLI (modules/flake/devshell.nix), used to add/bump
    # entries under ../../charts.
    nixhelm = {
      url = "github:farcaller/nixhelm";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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
