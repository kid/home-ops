# DO-NOT-EDIT. This file was auto-generated using github:denful/flake-file.
# Use `nix run .#write-flake` to regenerate it.
{
  description = "home-ops";

  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);

  nixConfig = {
    extra-substituters = [ "https://nixhelm.cachix.org" ];
    extra-trusted-public-keys = [ "nixhelm.cachix.org-1:esqauAsR4opRF0UsGrA6H3gD21OrzMnBBYvJXeddjtY=" ];
  };

  inputs = {
    den.url = "github:denful/den/f88d635baecb9f9a82e8b78002cfd28e940c187b";
    disko = {
      url = "github:AlexLov/disko/ff8702b4de27f72b4c78573dfb89ec74e36abdf1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko-zfs = {
      url = "github:numtide/disko-zfs/4a0e131be44004fcd8493c9249ab42016a90a4bb";
      inputs = {
        disko.follows = "disko";
        flake-parts.follows = "flake-parts";
        nixpkgs.follows = "nixpkgs";
      };
    };
    flake-file.url = "github:denful/flake-file/eccac77d2c2567efb6f368330930f3d55af8668a";
    flake-parts = {
      url = "github:hercules-ci/flake-parts/31729ca8cbdb4fa927b34e5f4353e6a83f39e993";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    git-hooks-nix = {
      url = "github:cachix/git-hooks.nix/0d3997c4d3253505f77c9bcea63904bb575da3c5";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    haumea = {
      url = "github:nix-community/haumea/v0.2.2";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    impermanence.url = "github:nix-community/impermanence/7b1d382faf603b6d264f58627330f9faa5cba149";
    import-tree.url = "github:vic/import-tree/eb1b52eaecc57f7c136d07ae8a93e724dfecac46";
    nh.url = "github:nix-community/nh/d2a7aa0c40cb0d2e1c433789e369c61fe63e1a76";
    nix-kube-generators.url = "github:farcaller/nix-kube-generators/810dcf792081790648ba9ae705b9a2286115ace8";
    nixhelm = {
      url = "github:farcaller/nixhelm/1ffea56dc6d4b603ad3a0d06a5977abcff3abe82";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixidy = {
      url = "github:arnarg/nixidy/c5c946319a7a2b65e8c8f3e59378387625dd109a";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-anywhere.url = "github:nix-community/nixos-anywhere/da83557d8b0bce57a52371b888ffd6d58724e55c";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    sops-nix = {
      url = "github:Mic92/sops-nix/2bd00bd9bb35fe6d114888c8f1c2e946c541dd8f";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix/27b3b12a8e6375f28ebe122f07d230ca5459bbfa";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
