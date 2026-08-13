# k3s bootstrap aspect — oneshot systemd services that apply manifests on
# first boot. Ported from nixopslab's modules/den/aspects/services/
# k3s-bootstrap.nix, scoped down to this repo's Phase 6 app set (cilium +
# coredns + argocd — no cert-manager/external-secrets/sops-operator/openebs
# yet, see modules/clusters/prd.nix).
#
# Bakes the generated manifests into the NixOS image via `self` (the flake
# source is a store path), so no git clone is needed on the node.
#
# Wave ordering:
#   0. k3s-bootstrap-namespaces — all Namespace resources from all apps
#                                  (cilium, coredns, argocd)
#   1. k3s-bootstrap-crds       — all CustomResourceDefinition resources from all apps,
#                                  wait for Established before proceeding
#   2. k3s-bootstrap-cilium     — Cilium core manifests, wait for operator
#                                  (operator registers Cilium CRDs at startup),
#                                  then apply Cilium custom resources
#   3. k3s-bootstrap-coredns    — CoreDNS deployment; ArgoCD needs cluster DNS to
#                                  resolve the git repository on first sync
#   4. k3s-bootstrap-argocd     — ArgoCD + self-managing Application
#
# Cilium does not ship CRDs in its Helm chart; the cilium-operator registers
# them at runtime. Applying Cilium*.yaml CRs before the operator is ready
# causes "no kind is registered" errors, hence the split in wave 2.
#
# Each service is idempotent: exits early if already installed.
{ self, ... }:
{
  den.aspects.k3s-bootstrap = {
    nixos =
      { pkgs, ... }:
      let
        manifestPath =
          name:
          builtins.path {
            path = self + "/manifests/prd/${name}";
            name = "k3s-prd-${builtins.replaceStrings [ "/" "." ] [ "-" "-" ] name}";
          };
        ciliumDir = manifestPath "cilium";
        corednsDir = manifestPath "coredns";
        argocdDir = manifestPath "argocd";
        bootstrapFile = manifestPath "bootstrap.yaml";
        waitForApi = ''
          echo "Waiting for k3s API server..."
          until kubectl get nodes >/dev/null 2>&1; do
            sleep 5
          done
        '';
      in
      {
        systemd.services = {
          # Wave 0: create all Namespace resources before any workloads
          k3s-bootstrap-namespaces = {
            description = "Bootstrap namespaces for all applications";
            after = [ "k3s.service" ];
            requires = [ "k3s.service" ];
            path = [
              pkgs.kubectl
              pkgs.findutils
            ];
            environment.KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = pkgs.writeShellScript "k3s-bootstrap-namespaces" ''
                set -e
                ${waitForApi}

                echo "Applying all Namespace resources..."
                declare -a files
                while IFS= read -r f; do files+=("-f" "$f"); done < <(
                  find ${ciliumDir} ${corednsDir} ${argocdDir} -name "Namespace-*.yaml" | sort
                )
                [[ ''${#files[@]} -gt 0 ]] && \
                  kubectl apply --server-side --force-conflicts --field-manager=argocd-controller "''${files[@]}"

                echo "Namespaces ready."
              '';
            };
            wantedBy = [ "multi-user.target" ];
          };

          # Wave 1: apply all CRDs and wait for them to be Established
          k3s-bootstrap-crds = {
            description = "Bootstrap CRDs for all applications";
            after = [
              "k3s.service"
              "k3s-bootstrap-namespaces.service"
            ];
            requires = [
              "k3s.service"
              "k3s-bootstrap-namespaces.service"
            ];
            path = [
              pkgs.kubectl
              pkgs.findutils
            ];
            environment.KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = pkgs.writeShellScript "k3s-bootstrap-crds" ''
                set -e

                echo "Applying all CRDs..."
                declare -a files
                while IFS= read -r f; do files+=("-f" "$f"); done < <(
                  find ${ciliumDir} ${argocdDir} -name "CustomResourceDefinition-*.yaml" | sort
                )
                [[ ''${#files[@]} -gt 0 ]] && \
                  kubectl apply --server-side --force-conflicts --field-manager=argocd-controller "''${files[@]}"

                echo "Waiting for ArgoCD CRDs to be established..."
                kubectl wait --for=condition=Established \
                  crd/applications.argoproj.io \
                  crd/applicationsets.argoproj.io \
                  crd/appprojects.argoproj.io \
                  --timeout=60s

                echo "CRDs ready."
              '';
            };
            wantedBy = [ "multi-user.target" ];
          };

          # Wave 2: Cilium CNI
          #
          # Cilium's Helm chart ships no CRDs — the cilium-operator registers
          # them at startup. We therefore split the apply in two:
          #   a) Core manifests (everything except Cilium* custom resources)
          #   b) Wait for cilium-operator rollout (CRDs now Established)
          #   c) Cilium custom resources (CiliumBGP*, CiliumLoadBalancerIPPool)
          k3s-bootstrap-cilium = {
            description = "Bootstrap Cilium CNI";
            after = [
              "k3s.service"
              "k3s-bootstrap-crds.service"
            ];
            requires = [
              "k3s.service"
              "k3s-bootstrap-crds.service"
            ];
            path = [
              pkgs.kubectl
              pkgs.findutils
            ];
            environment.KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = pkgs.writeShellScript "k3s-bootstrap-cilium" ''
                set -e

                if kubectl get daemonset -n kube-system cilium >/dev/null 2>&1; then
                  echo "Cilium already installed, skipping bootstrap."
                  exit 0
                fi

                echo "Applying Cilium core manifests..."
                declare -a core_files
                while IFS= read -r f; do core_files+=("-f" "$f"); done < <(
                  find ${ciliumDir} -name "*.yaml" ! -name "Cilium*.yaml" | sort
                )
                [[ ''${#core_files[@]} -gt 0 ]] && \
                  kubectl apply --server-side --force-conflicts --field-manager=argocd-controller "''${core_files[@]}"

                echo "Waiting for Cilium DaemonSet to be ready..."
                kubectl rollout status -n kube-system daemonset/cilium --timeout=300s

                echo "Waiting for Cilium operator to be ready..."
                kubectl rollout status -n kube-system deployment/cilium-operator --timeout=120s

                echo "Waiting for Cilium CRDs to be established..."
                until kubectl get crd ciliumloadbalancerippools.cilium.io >/dev/null 2>&1; do
                  sleep 5
                done
                kubectl wait --for=condition=Established \
                  crd/ciliumloadbalancerippools.cilium.io \
                  crd/ciliumbgpclusterconfigs.cilium.io \
                  crd/ciliumbgppeerconfigs.cilium.io \
                  crd/ciliumbgpadvertisements.cilium.io \
                  --timeout=60s

                echo "Applying Cilium custom resources..."
                declare -a cr_files
                while IFS= read -r f; do cr_files+=("-f" "$f"); done < <(
                  find ${ciliumDir} -name "Cilium*.yaml" | sort
                )
                [[ ''${#cr_files[@]} -gt 0 ]] && \
                  kubectl apply --server-side --force-conflicts --field-manager=argocd-controller "''${cr_files[@]}"

                echo "Cilium bootstrap complete."
              '';
            };
            wantedBy = [ "multi-user.target" ];
          };

          # Wave 3: CoreDNS — must be up before ArgoCD so its git sync can resolve hostnames
          k3s-bootstrap-coredns = {
            description = "Bootstrap CoreDNS cluster DNS";
            after = [
              "k3s.service"
              "k3s-bootstrap-cilium.service"
            ];
            requires = [
              "k3s.service"
              "k3s-bootstrap-cilium.service"
            ];
            path = [ pkgs.kubectl ];
            environment.KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = pkgs.writeShellScript "k3s-bootstrap-coredns" ''
                set -e

                if kubectl get deployment -n kube-system coredns >/dev/null 2>&1; then
                  echo "CoreDNS already installed, skipping bootstrap."
                  exit 0
                fi

                echo "Applying CoreDNS manifests..."
                kubectl apply \
                  --server-side --force-conflicts --field-manager=argocd-controller \
                  -f ${corednsDir}

                echo "Waiting for CoreDNS deployment to be ready..."
                kubectl rollout status -n kube-system deployment/coredns --timeout=120s

                echo "CoreDNS bootstrap complete."
              '';
            };
            wantedBy = [ "multi-user.target" ];
          };

          # Wave 4: ArgoCD — depends on CoreDNS for git hostname resolution
          k3s-bootstrap-argocd = {
            description = "Bootstrap ArgoCD and hand off to GitOps";
            after = [
              "k3s.service"
              "k3s-bootstrap-coredns.service"
            ];
            requires = [
              "k3s.service"
              "k3s-bootstrap-coredns.service"
            ];
            path = [ pkgs.kubectl ];
            environment.KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = pkgs.writeShellScript "k3s-bootstrap-argocd" ''
                set -e

                if kubectl get statefulset -n argocd argocd-application-controller >/dev/null 2>&1; then
                  echo "ArgoCD already installed, skipping bootstrap."
                  exit 0
                fi

                echo "Applying ArgoCD manifests..."
                kubectl apply \
                  --server-side --force-conflicts --field-manager=argocd-controller \
                  -f ${argocdDir}

                echo "Waiting for argocd-application-controller rollout..."
                kubectl rollout status -n argocd statefulset/argocd-application-controller --timeout=300s

                echo "Applying bootstrap Application..."
                kubectl apply \
                  --server-side --force-conflicts --field-manager=argocd-controller \
                  -f ${bootstrapFile}

                echo "Bootstrap complete — ArgoCD is now managing all applications from git."
              '';
            };
            wantedBy = [ "multi-user.target" ];
          };
        };
      };
  };
}
