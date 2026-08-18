# Seeds sops-operator's decryption secret from the cluster's sops-age key
# (modules/flake/provision-cluster-key.nix). sops-nix decrypts it straight
# from the committed ciphertext on every activation, using this host's own
# persisted SSH key (modules/flake/provision-host-key.nix) as its
# decryption identity — not a one-time nixos-anywhere --extra-files
# payload, so a rotated or newly-committed cluster key reaches the host on
# the next `deploy`, no reinstall required. modules/flake/sops-config.nix's
# clusterRule grants this host's own pubkey as a recipient on the cluster's
# committed key file for exactly that.
#
# A standalone oneshot, not joined to the k3s-bootstrap wave (modules/den/
# aspects/services/k3s/bootstrap.nix) — sops-operator itself is an
# ArgoCD-synced app (modules/kubernetes/sops-operator/default.nix), not
# part of that bootstrap chain, and nothing in that chain needs a secret.
{
  inputs,
  ...
}:
{
  flake-file.inputs.sops-nix = {
    url = "github:Mic92/sops-nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.k3s-sops-operator = {
    nixos =
      {
        host,
        pkgs,
        config,
        ...
      }:
      let
        clusterName = host.k3s.clusterName or "prd";
      in
      {
        imports = [ inputs.sops-nix.nixosModules.sops ];

        sops.secrets.sops-operator-age-key = {
          sopsFile = ../../../../../secrets/clusters/${clusterName}/sops-age-key.sops;
          format = "binary";
        };

        systemd.services.k3s-sops-operator-seed = {
          description = "Sync sops-operator's age key Secret";
          after = [ "k3s.service" ];
          requires = [ "k3s.service" ];
          path = [ pkgs.kubectl ];
          environment.KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            # Runs on every activation (sops-nix re-decrypts fresh each
            # time too), so a rotated key gets re-synced instead of only
            # ever being set once — kubectl apply, not create, for that.
            ExecStart = pkgs.writeShellScript "k3s-sops-operator-seed" ''
              set -e
              echo "Waiting for k3s API server..."
              until kubectl get nodes >/dev/null 2>&1; do
                sleep 5
              done

              echo "Waiting for sops-operator namespace..."
              until kubectl get namespace sops-operator >/dev/null 2>&1; do
                sleep 5
              done

              kubectl create secret generic sops-age-${clusterName} \
                -n sops-operator \
                --from-file=age.agekey=${config.sops.secrets.sops-operator-age-key.path} \
                --dry-run=client -o yaml | kubectl apply -f -
              kubectl label secret sops-age-${clusterName} -n sops-operator \
                sops.addons.projectcapsule.dev=true --overwrite

              echo "sops-age-${clusterName} synced."
            '';
          };
          wantedBy = [ "multi-user.target" ];
        };
      };
  };
}
