# DO-NOT-EDIT. This file was auto-generated using github:vic/flake-file.
# Use `nix run .#write-flake` to regenerate it.
{
  description = "home-ops";

  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);

  nixConfig = {
    extra-substituters = [ "https://nixhelm.cachix.org" ];
    extra-trusted-public-keys = [ "nixhelm.cachix.org-1:esqauAsR4opRF0UsGrA6H3gD21OrzMnBBYvJXeddjtY=" ];
  };

  inputs = {
    den.url = "github:denful/den/99cc0c5a1cc846cb1be681344b10d2731d430e13";
    disko = {
      url = "github:AlexLov/disko/6747342da148f6cb28c8405a70fe00455a0ba027";
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
    flake-file.url = "github:vic/flake-file/66ddd2f69a5c4677f0095c6f70eea1217dc45749";
    flake-parts = {
      url = "github:hercules-ci/flake-parts/31729ca8cbdb4fa927b34e5f4353e6a83f39e993";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    git-hooks-nix = {
      url = "github:cachix/git-hooks.nix/59f4ca0d063a1a3ec722c88b51a33004862e5379";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    haumea = {
      url = "github:nix-community/haumea/v0.2.2";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    impermanence.url = "github:nix-community/impermanence/7b1d382faf603b6d264f58627330f9faa5cba149";
    import-tree.url = "github:vic/import-tree/4ebb10ae17d5f1ad366e7aef5b92cb8eecf24f69";
    nh.url = "github:nix-community/nh/d2a7aa0c40cb0d2e1c433789e369c61fe63e1a76";
    nix-kube-generators.url = "github:farcaller/nix-kube-generators/810dcf792081790648ba9ae705b9a2286115ace8";
    nixhelm = {
      url = "github:farcaller/nixhelm/f706b6918a26b2c65d7ae9fd4f8bf9787cfd5b56";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixidy = {
      url = "github:arnarg/nixidy/c5c946319a7a2b65e8c8f3e59378387625dd109a";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-anywhere.url = "github:nix-community/nixos-anywhere/1c2f124e970fed2a49bd14ce0a8b4e9bff74d3b4";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    sops-nix = {
      url = "github:Mic92/sops-nix/7214124c20c1542c90deb54af50e2f53ae02711f";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix/27b3b12a8e6375f28ebe122f07d230ca5459bbfa";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
