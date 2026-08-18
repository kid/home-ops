# k3s bootstrap aspect — oneshot systemd services that apply manifests on
# first boot. Waves 0 and 1 sweep every app's rendered output under
# manifests/prd/ for Namespace/CRD resources, whatever the app — cheap and
# safe to apply early even for apps (miroir, sops-operator) whose own
# workloads are left for ArgoCD to bring up later. Waves 2 onward apply a
# specific, hand-picked subset of apps whose workloads the rest of the
# chain (or the node itself) needs up before ArgoCD takes over: cilium +
# cert-manager + coredns + argocd.
#
# Bakes the generated manifests into the NixOS image via `self` (the flake
# source is a store path), so no git clone is needed on the node.
#
# Wave ordering:
#   0. k3s-bootstrap-namespaces    — all Namespace resources, every app
#   1. k3s-bootstrap-crds          — all CustomResourceDefinition resources, every
#                                     app (including the upstream Gateway API CRDs,
#                                     modules/kubernetes/cilium/gateway-api-crds.nix),
#                                     wait for the ones later waves need to be
#                                     Established before proceeding
#   2. k3s-bootstrap-cilium        — Cilium core manifests, wait for operator
#                                     (operator registers Cilium CRDs at startup),
#                                     then apply Cilium custom resources. Skipped (fast
#                                     no-op) on hosts without den.aspects.k3s-cilium.
#   3. k3s-bootstrap-cert-manager  — cert-manager + the Hubble CA/ClusterIssuer
#                                     it signs (modules/kubernetes/cert-manager/
#                                     default.nix); must come after cilium since
#                                     cert-manager's pods need CNI to schedule
#                                     (unlike cilium-agent, which runs hostNetwork
#                                     and mounts Hubble's cert as `optional`, so it
#                                     doesn't block on this wave)
#   4. k3s-bootstrap-coredns       — CoreDNS deployment; ArgoCD needs cluster DNS to
#                                     resolve the git repository on first sync
#   5. k3s-bootstrap-argocd        — ArgoCD + self-managing Application
#
# Cilium does not ship CRDs in its Helm chart; the cilium-operator registers
# them at runtime. Applying Cilium*.yaml CRs before the operator is ready
# causes "no kind is registered" errors, hence the split in wave 2.
#
# Each service is idempotent: exits early if already installed.
{ self, den, ... }:
{
  den.aspects.k3s-bootstrap = {
    nixos =
      { host, pkgs, ... }:
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
        certManagerDir = manifestPath "cert-manager";
        bootstrapFile = manifestPath "bootstrap.yaml";
        # Every app's rendered output, namespaces and CRDs included — used by
        # waves 0 and 1 below so a new app (e.g. miroir, sops-operator) gets
        # its Namespace/CRD resources swept up automatically, instead of
        # each needing its own dir added to a hand-maintained list here.
        allManifestsDir = builtins.path {
          path = self + "/manifests/prd";
          name = "k3s-prd-all";
        };
        hasCilium = host.hasAspect den.aspects.k3s-cilium;
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
                  find ${allManifestsDir} -name "Namespace-*.yaml" | sort
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
                  find ${allManifestsDir} -name "CustomResourceDefinition-*.yaml" | sort
                )
                [[ ''${#files[@]} -gt 0 ]] && \
                  kubectl apply --server-side --force-conflicts --field-manager=argocd-controller "''${files[@]}"

                echo "Waiting for ArgoCD CRDs to be established..."
                kubectl wait --for=condition=Established \
                  crd/applications.argoproj.io \
                  crd/applicationsets.argoproj.io \
                  crd/appprojects.argoproj.io \
                  --timeout=60s

                echo "Waiting for cert-manager CRDs to be established..."
                kubectl wait --for=condition=Established \
                  crd/certificates.cert-manager.io \
                  crd/issuers.cert-manager.io \
                  crd/clusterissuers.cert-manager.io \
                  crd/certificaterequests.cert-manager.io \
                  crd/orders.acme.cert-manager.io \
                  crd/challenges.acme.cert-manager.io \
                  --timeout=60s

                echo "Waiting for Gateway API CRDs to be established..."
                kubectl wait --for=condition=Established \
                  crd/gatewayclasses.gateway.networking.k8s.io \
                  crd/gateways.gateway.networking.k8s.io \
                  crd/httproutes.gateway.networking.k8s.io \
                  crd/grpcroutes.gateway.networking.k8s.io \
                  crd/referencegrants.gateway.networking.k8s.io \
                  crd/backendtlspolicies.gateway.networking.k8s.io \
                  --timeout=60s

                echo "Waiting for sops-operator CRDs to be established..."
                kubectl wait --for=condition=Established \
                  crd/sopssecrets.addons.projectcapsule.dev \
                  crd/globalsopssecrets.addons.projectcapsule.dev \
                  crd/sopsproviders.addons.projectcapsule.dev \
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
              ExecStart = pkgs.writeShellScript "k3s-bootstrap-cilium" (
                if !hasCilium then
                  ''
                    echo "This host has no den.aspects.k3s-cilium — Cilium isn't its CNI, skipping bootstrap."
                  ''
                else
                  ''
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
                  ''
              );
            };
            wantedBy = [ "multi-user.target" ];
          };

          # Wave 3: cert-manager — after cilium, since cert-manager's own pods
          # need CNI to schedule. Once its webhook is up, apply the Hubble
          # self-signed CA + ClusterIssuer (modules/kubernetes/cert-manager/
          # default.nix) and wait for the CA to be signed, so Cilium's
          # hubble-server-certs Certificate (applied in wave 2) has a
          # working issuer to resolve against.
          k3s-bootstrap-cert-manager = {
            description = "Bootstrap cert-manager and the Hubble CA";
            after = [
              "k3s.service"
              "k3s-bootstrap-cilium.service"
            ];
            requires = [
              "k3s.service"
              "k3s-bootstrap-cilium.service"
            ];
            path = [
              pkgs.kubectl
              pkgs.findutils
            ];
            environment.KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = pkgs.writeShellScript "k3s-bootstrap-cert-manager" ''
                set -e

                if kubectl get deployment -n cert-manager cert-manager >/dev/null 2>&1; then
                  echo "cert-manager already installed, skipping bootstrap."
                  exit 0
                fi

                echo "Applying cert-manager core manifests..."
                declare -a core_files
                while IFS= read -r f; do core_files+=("-f" "$f"); done < <(
                  find ${certManagerDir} -name "*.yaml" \
                    ! -name "ClusterIssuer-*.yaml" ! -name "Certificate-*.yaml" | sort
                )
                [[ ''${#core_files[@]} -gt 0 ]] && \
                  kubectl apply --server-side --force-conflicts --field-manager=argocd-controller "''${core_files[@]}"

                echo "Waiting for cert-manager rollout..."
                kubectl rollout status -n cert-manager deployment/cert-manager --timeout=120s
                kubectl rollout status -n cert-manager deployment/cert-manager-webhook --timeout=120s
                kubectl rollout status -n cert-manager deployment/cert-manager-cainjector --timeout=120s

                echo "Applying Hubble CA issuer chain..."
                declare -a issuer_files
                while IFS= read -r f; do issuer_files+=("-f" "$f"); done < <(
                  find ${certManagerDir} -name "ClusterIssuer-*.yaml" -o -name "Certificate-*.yaml" | sort
                )
                [[ ''${#issuer_files[@]} -gt 0 ]] && \
                  kubectl apply --server-side --force-conflicts --field-manager=argocd-controller "''${issuer_files[@]}"

                echo "Waiting for the Hubble CA to be signed..."
                kubectl wait --for=condition=Ready certificate/hubble-ca -n cert-manager --timeout=60s

                echo "cert-manager bootstrap complete."
              '';
            };
            wantedBy = [ "multi-user.target" ];
          };

          # Wave 4: CoreDNS — must be up before ArgoCD so its git sync can resolve hostnames
          k3s-bootstrap-coredns = {
            description = "Bootstrap CoreDNS cluster DNS";
            after = [
              "k3s.service"
              "k3s-bootstrap-cert-manager.service"
            ];
            requires = [
              "k3s.service"
              "k3s-bootstrap-cert-manager.service"
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

          # Wave 5: ArgoCD — depends on CoreDNS for git hostname resolution
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
