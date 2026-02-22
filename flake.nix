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
        {
          config,
          pkgs,
          ...
        }:
        {
          treefmt = {
            flakeCheck = true;
            settings.excludes = [
              "*.sops.*"
            ];
            programs = {
              nixfmt.enable = true;
              hclfmt.enable = true;
              just.enable = true;
              terraform.enable = true;
              terraform.includes = [
                "*.tofu"
                "*.tfvars"
                "*.tftest.hcl"
              ];
              yamlfmt.enable = true;
              yamlfmt.settings = {
                formatter = {
                  indent = 2;
                  indentless_arrays = false;
                  include_document_start = true;
                  eof_newline = true;
                  trim_trailing_blank_lines = true;
                  retain_line_breaks_single = true;
                };
              };
            };
          };
          devShells.default = pkgs.mkShell {
            packages = with pkgs; [
              watch
              just
              yq
              gum
              minijinja
              expect
              age
              sops
              opentofu
              tofu-ls
              terragrunt

              talhelper
              talosctl
              kubectl
              kubernetes-helm
              cilium-cli
              kustomize
              kustomize-sops
              kubectx
              fluxcd-operator
              fluxcd-operator-mcp

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
