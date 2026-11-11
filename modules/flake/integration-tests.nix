# NixOS VM integration tests: `nix build -L .#integration-tests.<name>`.
# Under legacyPackages, not checks or packages, so `nix flake check` neither
# builds nor evaluates them: each boots VMs for minutes. CI's
# `integration-tests` job (.github/workflows/nix-flake-check.yaml) builds
# them on the self-hosted runner, which hands them to the nix builders.
{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      legacyPackages.integration-tests = import ../../tests/integration/k3s.nix {
        inherit pkgs inputs;
        modulesTree = inputs.import-tree ../.;
      };
    };
}
