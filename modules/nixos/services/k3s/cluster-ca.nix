# The cluster CA (the cert-manager `cluster-ca` ClusterIssuer, distributed by
# trust-manager as the `cluster-ca` ConfigMap), from
# secrets/clusters/<cluster>/cluster-ca.sops (`nix run .#provision-cluster-ca
# <cluster>`). Seeded as the cert-manager/cluster-ca Secret on every boot, so
# a rebuilt cluster keeps the CA its clients pin (Home Assistant's MQTT entry,
# zigbee2mqtt, Frigate) instead of cert-manager self-signing a new one.
#
# Part of the bootstrap: its cert-manager step waits for the cluster-ca
# ClusterIssuer, which Cilium's Hubble certificates need.
{ inputs, den, ... }:
{
  den.aspects.k3s.cluster-ca.nixos =
    {
      host,
      pkgs,
      config,
      ...
    }:
    let
      inherit (host.settings.k3s) clusterName;
      sopsFile = ../../../../secrets/clusters/${clusterName}/cluster-ca.sops;
      secret = key: {
        inherit sopsFile key;
        format = "yaml";
      };
      path = key: config.sops.secrets."cluster-ca/${key}".path;
    in
    {
      imports = [ inputs.sops-nix.nixosModules.sops ];

      assertions = [
        {
          assertion = builtins.pathExists sopsFile;
          message = "secrets/clusters/${clusterName}/cluster-ca.sops is missing: run `nix run .#provision-cluster-ca ${clusterName}`.";
        }
      ];

      sops.secrets = {
        "cluster-ca/tls.crt" = secret "tls.crt";
        "cluster-ca/tls.key" = secret "tls.key";
        "cluster-ca/ca.crt" = secret "ca.crt";
      };

      systemd.services.k3s-cluster-ca-seed = {
        description = "Sync the cluster CA Secret";
        after = [
          "k3s.service"
          "sops-install-secrets.service"
          "k3s-bootstrap-namespaces.service"
        ];
        requires = [ "k3s.service" ];
        # Only exists with sops.useSystemdActivation, as in token.nix.
        wants = [ "sops-install-secrets.service" ];
        path = [ pkgs.kubectl ];
        environment.KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = pkgs.writeShellScript "k3s-cluster-ca-seed" ''
            set -eo pipefail
            echo "Waiting for k3s API server..."
            until kubectl get nodes >/dev/null 2>&1; do
              sleep 5
            done

            echo "Waiting for cert-manager namespace..."
            until kubectl get namespace cert-manager >/dev/null 2>&1; do
              sleep 5
            done

            for f in ${path "tls.crt"} ${path "tls.key"} ${path "ca.crt"}; do
              if [ ! -s "$f" ]; then
                echo "decrypted $f is empty, refusing to seed" >&2
                exit 1
              fi
            done

            # Server-side: a client-side apply would copy the private key into
            # the last-applied-configuration annotation.
            kubectl create secret generic cluster-ca \
              -n cert-manager \
              --type=kubernetes.io/tls \
              --from-file=tls.crt=${path "tls.crt"} \
              --from-file=tls.key=${path "tls.key"} \
              --from-file=ca.crt=${path "ca.crt"} \
              --dry-run=client -o yaml \
              | kubectl apply --server-side --force-conflicts --field-manager=k3s-cluster-ca-seed -f -

            echo "cluster-ca synced."
          '';
        };
        wantedBy = [ "multi-user.target" ];
      };
    };

  den.aspects.k3s.bootstrap.includes = [ den.aspects.k3s.cluster-ca ];
}
