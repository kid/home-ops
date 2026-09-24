# nix-flake-check runs on pre-push rather than pre-commit so commits stay fast.
{ inputs, ... }:
{
  flake-file.inputs.git-hooks-nix = {
    url = "github:cachix/git-hooks.nix/0d3997c4d3253505f77c9bcea63904bb575da3c5";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  imports = [ inputs.git-hooks-nix.flakeModule ];

  perSystem = {
    pre-commit.settings.hooks = {
      treefmt.enable = true;

      nix-flake-check = {
        enable = true;
        name = "nix flake check";
        entry = "nix flake check";
        language = "system";
        pass_filenames = false;
        stages = [ "pre-push" ];
      };
    };
  };
}
