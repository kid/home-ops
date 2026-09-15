{
  inputs,
  ...
}:
{
  den.aspects.k3s-external-secrets = {
    nixos =
      {
        host,
        pkgs,
        lib,
        config,
        ...
      }:
      let
        clusterName = host.k3s.clusterName or "prd";
      in
      {
        imports = [ inputs.sops-nix.nixosModules.sops ];

        sops.secrets.onepassword-service-account-token = {
          sopsFile = ../../../../../secrets/clusters/${clusterName}/onepassword-service-account-token.sops;
          format = "binary";
        };

        sops.useSystemdActivation = lib.mkIf config.services.cloud-init.enable true;
        systemd.services.sops-install-secrets = lib.mkIf config.services.cloud-init.enable {
          after = [ "cloud-config.service" ];
          wants = [ "cloud-config.service" ];
        };

        systemd.services.k3s-external-secrets-seed = {
          description = "Sync the 1Password service account token Secret";
          after = [ "k3s.service" ];
          requires = [ "k3s.service" ];
          path = [ pkgs.kubectl ];
          environment.KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = pkgs.writeShellScript "k3s-external-secrets-seed" ''
              set -e
              echo "Waiting for k3s API server..."
              until kubectl get nodes >/dev/null 2>&1; do
                sleep 5
              done

              echo "Waiting for external-secrets namespace..."
              until kubectl get namespace external-secrets >/dev/null 2>&1; do
                sleep 5
              done

              kubectl create secret generic onepassword-service-account-token \
                -n external-secrets \
                --from-literal=token="$(cat ${config.sops.secrets.onepassword-service-account-token.path})" \
                --dry-run=client -o yaml | kubectl apply -f -

              echo "onepassword-service-account-token synced."
            '';
          };
          wantedBy = [ "multi-user.target" ];
        };
      };
  };
}
