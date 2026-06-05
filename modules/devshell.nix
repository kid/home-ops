{ inputs, ... }:
{
  flake-file.inputs = {
    treefmt-nix.url = "github:numtide/treefmt-nix";
  };

  imports = [ inputs.treefmt-nix.flakeModule ];

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
          # yamlfmt.enable = true;
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
          expect
          age
          sops
          opentofu
          tofu-ls
          terragrunt

          go
          gotestsum

          talhelper
          talosctl
          kubectl
          kubernetes-helm
          cilium-cli
          kustomize
          kustomize-sops
          kubectx
          fluxcd
          fluxcd-operator
          fluxcd-operator-mcp
          mcp-grafana
          helmfile
          kubevirt
          nodejs

          nil
          nixd
        ];

        inputsFrom = [ config.treefmt.build.devShell ];
      };
    };
}
