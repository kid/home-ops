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
      url = "github:hercules-ci/flake-parts/17c9d6cdfc60c64f4ee8d306f9bc0b4ccb51481e";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    git-hooks-nix = {
      url = "github:cachix/git-hooks.nix/43b3c1ab9d40fb1dbb008f451988a91e375825e9";
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
      url = "github:farcaller/nixhelm/8a19607cd16231e1f92e10174ff562f9c6d52984";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixidy = {
      url = "github:arnarg/nixidy/4682f760ddcae469bd4e6eec7aeb70e20505a4ed";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-anywhere.url = "github:nix-community/nixos-anywhere/1c2f124e970fed2a49bd14ce0a8b4e9bff74d3b4";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    sops-nix = {
      url = "github:Mic92/sops-nix/a8627b21b9107c5711c96b84f32a9a4b3d45295f";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix/df3c0640565d04a0261253cdd89fce78ec50168a";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
