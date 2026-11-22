# nix run .#provision-cluster-ca <cluster> — generates a self-signed 10-year
# ECDSA P-256 CA (CN cluster-ca) and sops-encrypts it into
# secrets/clusters/<cluster>/cluster-ca.sops as tls.crt/tls.key/ca.crt, for
# den.aspects.k3s.cluster-ca. The key only ever goes through pipes, never a
# plaintext file. Replacing an existing CA breaks every client that pins it,
# so this skips a cluster that already has one.
{
  perSystem =
    { pkgs, config, ... }:
    {
      packages.provision-cluster-ca = pkgs.writeShellApplication {
        name = "provision-cluster-ca";
        runtimeInputs = [
          pkgs.jq
          pkgs.openssl
          pkgs.sops
        ];
        text = ''
          cluster=''${1:?usage: provision-cluster-ca <cluster>}
          sops_file="secrets/clusters/$cluster/cluster-ca.sops"

          if [[ -f "$sops_file" ]]; then
            echo "==> $cluster already has a CA ($sops_file), skipping generation."
            exit 0
          fi

          mkdir -p "$(dirname "$sops_file")"
          echo "==> Generating a cluster CA for $cluster..."
          key="$(openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256)"
          crt="$(
            openssl req -x509 -new -key <(printf '%s\n' "$key") \
              -subj /CN=cluster-ca -days 3650 \
              -addext basicConstraints=critical,CA:TRUE \
              -addext keyUsage=critical,digitalSignature,keyCertSign,cRLSign
          )"
          # Through the environment, not argv: /proc/<pid>/cmdline is world-readable.
          KEY="$key" CRT="$crt" jq -n '{"tls.crt": "\(env.CRT)\n", "tls.key": "\(env.KEY)\n", "ca.crt": "\(env.CRT)\n"}' \
            | sops --input-type json --output-type yaml --encrypt \
              --filename-override "$sops_file" --output "$sops_file" /dev/stdin

          echo "==> Wrote $sops_file: commit it before deploying the cluster's server."
        '';
      };

      apps.provision-cluster-ca = {
        type = "app";
        program = "${config.packages.provision-cluster-ca}/bin/provision-cluster-ca";
      };
    };
}
