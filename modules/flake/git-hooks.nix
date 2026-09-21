# nix-flake-check runs on pre-push rather than pre-commit so commits stay fast.
{ inputs, ... }:
{
  flake-file.inputs.git-hooks-nix = {
    url = "github:cachix/git-hooks.nix/43b3c1ab9d40fb1dbb008f451988a91e375825e9";
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
