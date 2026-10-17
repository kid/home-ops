# Auto-loads pkgs/by-name/<name>/package.nix as packages.<name>, same
# directory shape as nixpkgs' own pkgs/by-name (minus its two-letter
# nesting) — for small local packages not (yet) in nixpkgs.
{ inputs, ... }:
{
  flake-file.inputs.pkgs-by-name-for-flake-parts.url = "github:drupol/pkgs-by-name-for-flake-parts";

  imports = [ inputs.pkgs-by-name-for-flake-parts.flakeModule ];

  perSystem.pkgsDirectory = ../../pkgs/by-name;
}
