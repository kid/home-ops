# Seeds sops-operator's decryption secret from the cluster's sops-age key
# (modules/flake/provision-cluster-key.nix), delivered onto disk at install
# time via modules/flake/nixos-anywhere.nix's --extra-files staging. A
# standalone oneshot, not joined to the k3s-bootstrap wave (modules/den/
# aspects/services/k3s/bootstrap.nix) — sops-operator itself is an
# ArgoCD-synced app (modules/kubernetes/sops-operator/default.nix), not
# part of that bootstrap chain, and nothing in that chain needs a secret.
{
  den.aspects.k3s-sops-operator = {
    persist.files = [ "/etc/sops-operator/age-key" ];

    nixos =
      { pkgs, ... }:
      {
        systemd.services.k3s-sops-operator-seed = {
          description = "Seed sops-operator's age key Secret";
          after = [ "k3s.service" ];
          requires = [ "k3s.service" ];
          path = [ pkgs.kubectl ];
          environment.KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = pkgs.writeShellScript "k3s-sops-operator-seed" ''
              set -e
              echo "Waiting for k3s API server..."
              until kubectl get nodes >/dev/null 2>&1; do
                sleep 5
              done

              if kubectl get secret sops-age-prd -n sops-operator >/dev/null 2>&1; then
                echo "sops-age-prd already exists."
                exit 0
              fi

              echo "Waiting for sops-operator namespace..."
              until kubectl get namespace sops-operator >/dev/null 2>&1; do
                sleep 5
              done

              kubectl create secret generic sops-age-prd \
                -n sops-operator \
                --from-file=age.agekey=/etc/sops-operator/age-key
              kubectl label secret sops-age-prd -n sops-operator \
                sops.addons.projectcapsule.dev=true

              echo "sops-age-prd created."
            '';
          };
          wantedBy = [ "multi-user.target" ];
        };
      };
  };
}
