# NixOS VM integration tests: `nix build -L .#integration-tests.<name>`.
# Under legacyPackages, not checks or packages, so `nix flake check` (and CI)
# neither builds nor evaluates them: each boots VMs for minutes.
{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      args = {
        inherit pkgs inputs;
        modulesTree = inputs.import-tree ../.;
      };
    in
    {
      legacyPackages.integration-tests =
        import ../../tests/integration/k3s.nix args // import ../../tests/integration/impermanence.nix args;
    };
}
