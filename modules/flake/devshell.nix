# devShell, carried over from the pre-dendritic flake.nix. treefmt config
# lives in modules/flake/formatter.nix, git hooks in modules/flake/git-hooks.nix.
{ inputs, ... }: {
  perSystem =
    {
      config,
      pkgs,
      lib,
      system,
      ...
    }:
    {
      # 1password-cli is unfree; flake-parts' own nixpkgs module (module/
      # nixpkgs.nix) sets perSystem's `pkgs` via `_module.args.pkgs =
      # mkOptionDefault (...)`, so redefining it here (repo-wide, not just
      # this file — `pkgs` is a single per-system arg) overrides that
      # default. Scoped to exactly this one package rather than a blanket
      # `allowUnfree = true`.
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "1password-cli" ];
      };

      devShells.default = pkgs.mkShell {
        packages =
          with pkgs;
          [
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
            _1password-cli
            secretspec

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
          ]
          ++ [
            config.packages.deploy
            config.packages.nixos-anywhere-install
            config.packages.write-manifests
            config.packages.write-terragrunt
            config.packages.write-flake
            config.packages.write-lock
            config.packages.write-inputs
          ];

        inputsFrom = [
          config.treefmt.build.devShell
          config.pre-commit.devShell
        ];
      };
    };
}
