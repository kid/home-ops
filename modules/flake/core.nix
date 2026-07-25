# Core flake setup: imports den (aspect-oriented module system) and
# flake-file's dendritic module (auto-generates flake.nix, import-tree ./modules
# wiring). Mirrors nixopslab's modules/flake/core.nix.
{ inputs, ... }:
{
  imports = [
    inputs.den.flakeModules.default
    inputs.flake-file.flakeModules.dendritic
  ];

  systems = [ "x86_64-linux" ];
}
