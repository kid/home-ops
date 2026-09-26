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
          # sops-nix's own systemd-activation mode adds `before = [ "sysinit.target" ]`,
          # which conflicts with waiting on cloud-init (itself ordered after
          # sysinit.target) and forms a cycle systemd breaks by dropping this
          # unit from the boot entirely. The age key (an SSH host key) only
          # exists once cloud-init writes it, so this host can't decrypt
          # before sysinit.target anyway; drop that participation instead.
          wantedBy = lib.mkForce [ "multi-user.target" ];
          before = lib.mkForce [ ];
        };

        systemd.services.k3s-external-secrets-seed = {
          description = "Sync the 1Password service account token Secret";
          after = [
            "k3s.service"
            "sops-install-secrets.service"
          ];
          requires = [
            "k3s.service"
            "sops-install-secrets.service"
          ];
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

              token="$(cat ${config.sops.secrets.onepassword-service-account-token.path})"
              if [ -z "$token" ]; then
                echo "decrypted onepassword-service-account-token is empty, refusing to seed" >&2
                exit 1
              fi

              kubectl create secret generic onepassword-service-account-token \
                -n external-secrets \
                --from-literal=token="$token" \
                --dry-run=client -o yaml | kubectl apply -f -

              echo "onepassword-service-account-token synced."
            '';
          };
          wantedBy = [ "multi-user.target" ];
        };
      };
  };
}
