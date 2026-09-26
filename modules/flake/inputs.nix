# Core flake inputs: nixpkgs, flake-parts (carried over from the
# pre-dendritic flake.nix), plus den/flake-file/import-tree for the
# dendritic module system used to generate tf-stacks/prd/network's
# terragrunt.hcl leaves from Nix (see modules/den/batteries/terragrunt/*.nix).
# sops-nix lives here too, not next to its one current consumer
# (modules/den/aspects/services/k3s/external-secrets.nix): it's generic
# secrets-decryption plumbing any future NixOS aspect can pull in, not
# something owned by that aspect specifically.
_: {
  flake-file.description = "home-ops";

  flake-file.inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-parts = {
      url = "github:hercules-ci/flake-parts/31729ca8cbdb4fa927b34e5f4353e6a83f39e993";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    den.url = "github:denful/den/99cc0c5a1cc846cb1be681344b10d2731d430e13";

    flake-file.url = "github:denful/flake-file/eccac77d2c2567efb6f368330930f3d55af8668a";

    import-tree.url = "github:vic/import-tree/eb1b52eaecc57f7c136d07ae8a93e724dfecac46";

    sops-nix = {
      url = "github:Mic92/sops-nix/2bd00bd9bb35fe6d114888c8f1c2e946c541dd8f";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
