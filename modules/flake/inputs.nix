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

    den.url = "github:denful/den/d0d80faa36f735c9390c1f6e0a3a481ae7ae31d0";

    flake-file.url = "github:denful/flake-file/de3e0fcfe03b1af5d36b95952f216ea9ba087c8a";

    import-tree.url = "github:vic/import-tree/eb1b52eaecc57f7c136d07ae8a93e724dfecac46";

    sops-nix = {
      url = "github:Mic92/sops-nix/5efb5a6f4f5ab192817d28557dd4d650fa14d866";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
