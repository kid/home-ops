# Exposes Helm chart derivations from nixhelm as a flake output, so k8s-
# manifests aspects can reference `charts.<repo>.<chart>` without depending
# on the nixhelm input directly. Ported verbatim from nixopslab's
# modules/flake/charts.nix.
{
  inputs,
  config,
  lib,
  ...
}:
{
  flake-file.inputs.nixhelm = {
    url = "github:farcaller/nixhelm";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  flake.chartsDerivations = lib.genAttrs config.systems (
    system: inputs.nixhelm.chartsDerivations.${system}
  );
}
