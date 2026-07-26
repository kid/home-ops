# treefmt config, split out from devshell.nix. Mirrors nixopslab's
# modules/flake/formatter.nix.
{ inputs, ... }:
{
  flake-file.inputs.treefmt-nix = {
    url = "github:numtide/treefmt-nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  imports = [ inputs.treefmt-nix.flakeModule ];

  perSystem = {
    treefmt = {
      flakeCheck = true;
      settings.excludes = [
        "*.sops.*"
        # nixidy-generated (modules/flake/files.nix); nixidy has its own
        # idempotent YAML output, no document-start marker — don't fight it.
        "manifests/**"
      ];
      programs = {
        nixfmt.enable = true;
        deadnix.enable = true;
        statix.enable = true;
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
  };
}
