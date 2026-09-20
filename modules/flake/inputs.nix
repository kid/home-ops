# Core flake inputs: nixpkgs, flake-parts (carried over from the
# pre-dendritic flake.nix), plus den/flake-file/import-tree for the
# dendritic module system used to generate tf-stacks/prd/network's
# terragrunt.hcl leaves from Nix (see modules/den/batteries/terragrunt/*.nix).
_: {
  flake-file.description = "home-ops";

  flake-file.inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-parts = {
      url = "github:hercules-ci/flake-parts/17c9d6cdfc60c64f4ee8d306f9bc0b4ccb51481e";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    den.url = "github:denful/den/99cc0c5a1cc846cb1be681344b10d2731d430e13";

    flake-file.url = "github:vic/flake-file/66ddd2f69a5c4677f0095c6f70eea1217dc45749";

    import-tree.url = "github:vic/import-tree/4ebb10ae17d5f1ad366e7aef5b92cb8eecf24f69";
  };
}
