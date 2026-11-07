{ inputs, ... }:
{
  flake-file.inputs.git-hooks-nix = {
    url = "github:cachix/git-hooks.nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  imports = [ inputs.git-hooks-nix.flakeModule ];

  perSystem = {
    pre-commit.settings.hooks.treefmt.enable = true;
  };
}
