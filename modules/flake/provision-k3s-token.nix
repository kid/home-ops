# nix run .#provision-k3s-token <cluster> — generates a random k3s join
# token and sops-encrypts it into secrets/clusters/<cluster>/k3s-token.sops,
# for den.aspects.k3s-token. Only for a cluster that has not started yet: a
# running server refuses any token but the one it was bootstrapped with.
{
  perSystem =
    { pkgs, config, ... }:
    {
      packages.provision-k3s-token = pkgs.writeShellApplication {
        name = "provision-k3s-token";
        runtimeInputs = [
          pkgs.openssl
          pkgs.sops
        ];
        text = ''
          cluster=''${1:?usage: provision-k3s-token <cluster>}
          sops_file="secrets/clusters/$cluster/k3s-token.sops"

          if [[ -f "$sops_file" ]]; then
            echo "==> $cluster already has a token ($sops_file), skipping generation."
            exit 0
          fi

          mkdir -p "$(dirname "$sops_file")"
          echo "==> Generating a k3s token for $cluster..."
          openssl rand -hex 32 \
            | sops --input-type binary --output-type binary --encrypt \
              --filename-override "$sops_file" --output "$sops_file" /dev/stdin

          echo "==> Committed: $sops_file"
        '';
      };

      apps.provision-k3s-token = {
        type = "app";
        program = "${config.packages.provision-k3s-token}/bin/provision-k3s-token";
      };
    };
}
