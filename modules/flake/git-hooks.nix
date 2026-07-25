# git-hooks-nix wires pre-commit-style git hooks. treefmt runs on
# pre-commit (fast, auto-detected from modules/flake/formatter.nix since
# `config.treefmt` exists); the full `nix flake check` — treefmt's own
# flakeCheck plus checks.terragrunt — runs on pre-push so pushes can't
# carry stale terragrunt leaves or unformatted files.
{ inputs, ... }:
{
  flake-file.inputs.git-hooks-nix = {
    url = "github:cachix/git-hooks.nix";
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
