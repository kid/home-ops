# devShell, carried over from the pre-dendritic flake.nix. treefmt config
# lives in modules/flake/formatter.nix, git hooks in modules/flake/git-hooks.nix.
_: {
  perSystem =
    {
      config,
      pkgs,
      ...
    }:
    {
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
