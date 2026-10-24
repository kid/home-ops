# NixOS VM integration tests: `nix build -L .#integration-tests.<name>`.
# Under legacyPackages, not checks or packages, so `nix flake check` (CI and
# the pre-push hook) neither builds nor evaluates them: each boots VMs for
# minutes.
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
