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
      url = "github:hercules-ci/flake-parts/024633cd702b10285db5cb19b40ad48d2399ba60";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    den.url = "github:denful/den/7594405b45e0ce2d5a418fe104a26e17f6b1dd8f";

    flake-file.url = "github:denful/flake-file/91280a19eede3b3035e3889a3523c27e8fc07886";

    import-tree.url = "github:vic/import-tree/eb1b52eaecc57f7c136d07ae8a93e724dfecac46";

    sops-nix = {
      url = "github:Mic92/sops-nix/dcd241ba97088c22569d1573286e1b9daad340c0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
