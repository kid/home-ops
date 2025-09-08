{
  description = "Description for the project";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    devshell.url = "github:numtide/devshell";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    devenv.url = "github:cachix/devenv";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.devenv.flakeModule
        inputs.treefmt-nix.flakeModule
      ];
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      perSystem =
        {
          pkgs,
          ...
        }:
        {
          devenv.shells.default = {
            packages = with pkgs; [
              sops
              tofu-ls
              terragrunt
            ];

            languages = {
              nix.enable = true;
              # go = {
              #   enable = true;
              #   package = pkgs.go_1_24;
              # };
              terraform = {
                enable = true;
                package = pkgs.opentofu;
              };
            };
          };
        };
    };
}
