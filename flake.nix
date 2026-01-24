{
  description = "Description for the project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.treefmt-nix.flakeModule
      ];

      systems = [
        "x86_64-linux"
      ];

      perSystem =
        { config, pkgs, ... }:
        {
          treefmt = {
            flakeCheck = true;
            programs = {
              nixfmt.enable = true;
              hclfmt.enable = true;
              terraform.enable = true;
              terraform.includes = [
                "*.tofu"
                "*.tfvars"
                "*.tftest.hcl"
              ];
            };
          };
          devShells.default = pkgs.mkShell {
            packages = with pkgs; [
              just
              expect
              sops
              opentofu
              tofu-ls
              terragrunt

              talhelper
              talosctl
              kubectl
              kubernetes-helm
              cilium-cli
              argocd
              kustomize
              kubectx

              nil
              nixd
            ];

            inputsFrom = [ config.treefmt.build.devShell ];

            shellHook = ''
              alias ssh='ssh -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking=no"'
            '';
          };
        };
    };
}
