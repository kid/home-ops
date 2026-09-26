# ArgoCD, sourced as static manifests (argoproj/argo-cd's own
# manifests/cluster-install kustomization) rather than a Helm chart — same
# approach nixopslab's modules/den/aspects/kubernetes/argocd/default.nix uses, ported
# verbatim here. Once applied (modules/den/aspects/services/k3s/bootstrap.nix),
# ArgoCD syncs manifests/prd/bootstrap.yaml and takes over managing itself
# and every other app aspect from git.
{ lib, ... }:
let
  inherit (lib) types mkOption mkIf;
in
{
  den.aspects.kubernetes.argocd.k8s-manifests =
    {
      config,
      lib,
      pkgs,
      cluster,
      ...
    }:
    {
      options.services.argocd = with lib; {
        enable = mkOption {
          type = types.bool;
          default = true;
        };

        values = mkOption {
          type = types.attrsOf types.anything;
          default = { };
        };
      };

      config = mkIf config.services.argocd.enable {
        applications.argocd = {
          namespace = "argocd";

          kustomize.applications.argocd = {
            namespace = "argocd";
            kustomization = {
              src = pkgs.fetchFromGitHub {
                owner = "argoproj";
                repo = "argo-cd";
                # renovate: datasource=github-releases depName=argoproj/argo-cd
                rev = "v3.5.3";
                hash = "sha256-9Q+t9a5tYIiWYoJ2IM9OjCkT6+ZnjjwEMlq7fUsXv5E=";
              };
              path = "manifests/cluster-install";
            };
          };

          resources.appProjects.default.spec = {
            clusterResourceWhitelist = [
              {
                group = "*";
                kind = "*";
              }
            ];
            destinations = [
              {
                namespace = "*";
                server = "*";
              }
            ];
            sourceRepos = [ "*" ];
          };

          # Pairs with syncOptions.serverSideApply (nixidy-defaults.nix): diffs
          # against the real server-applied result, not a client-side guess.
          resources.configMaps.argocd-cmd-params-cm.data."controller.diff.server.side" = "true";

          # ArgoCD ships no health check for Application either. Without one a
          # child Application counts as healthy the moment it exists, so the
          # sync-wave annotations on the Applications in manifests/*/apps
          # order nothing: the next wave starts seconds later, while the
          # previous app's pods are still starting.
          resources.configMaps.argocd-cm.data."resource.customizations.health.argoproj.io_Application" = ''
            hs = {}
            hs.status = "Progressing"
            hs.message = ""
            if obj.status ~= nil and obj.status.health ~= nil then
              hs.status = obj.status.health.status
              if obj.status.health.message ~= nil then
                hs.message = obj.status.health.message
              end
            end
            return hs
          '';

          # ArgoCD has no built-in health check for ExternalSecret, so it
          # considers one healthy the instant it's applied — before ESO has
          # actually pulled anything. This is what makes every sync-wave
          # ordering gated on an ExternalSecret's health mean anything.
          resources.configMaps.argocd-cm.data."resource.customizations.health.external-secrets.io_ExternalSecret" =
            ''
              hs = {}
              if obj.status ~= nil and obj.status.conditions ~= nil then
                for i, condition in ipairs(obj.status.conditions) do
                  if condition.type == "Ready" and condition.status == "True" then
                    hs.status = "Healthy"
                    hs.message = condition.message
                    return hs
                  end
                end
              end
              hs.status = "Progressing"
              hs.message = "Waiting for ExternalSecret to sync"
              return hs
            '';

          # Same reason as ExternalSecret above: a PushSecret is healthy only
          # once it has actually pushed.
          resources.configMaps.argocd-cm.data."resource.customizations.health.external-secrets.io_PushSecret" =
            ''
              hs = {}
              if obj.status ~= nil and obj.status.conditions ~= nil then
                for i, condition in ipairs(obj.status.conditions) do
                  if condition.type == "Ready" and condition.status == "True" then
                    hs.status = "Healthy"
                    hs.message = condition.message
                    return hs
                  end
                end
              end
              hs.status = "Progressing"
              hs.message = "Waiting for PushSecret to sync"
              return hs
            '';

          # Replaces argocd-server's ephemeral self-signed cert with one off Hubble's CA.
          resources.certificates.argocd-server-tls.spec = {
            secretName = "argocd-server-tls";
            dnsNames = [
              "argocd-server"
              "argocd-server.argocd.svc.cluster.local"
            ];
            issuerRef = {
              name = "hubble-ca-issuer";
              kind = "ClusterIssuer";
              group = "cert-manager.io";
            };
          };

          # internal-ca ConfigMap comes from trust-manager/default.nix's Bundle.
          resources.backendTLSPolicies.argocd-server.spec = {
            targetRefs = [
              {
                kind = "Service";
                name = "argocd-server";
                group = "";
              }
            ];
            validation = {
              hostname = "argocd-server.argocd.svc.cluster.local";
              caCertificateRefs = [
                {
                  kind = "ConfigMap";
                  name = "internal-ca";
                  group = "";
                }
              ];
            };
          };

          resources.httpRoutes.argocd.spec = {
            parentRefs = [
              {
                group = "gateway.networking.k8s.io";
                kind = "Gateway";
                name = "apps";
                namespace = "envoy-gateway-system";
                sectionName = "https";
              }
            ];
            hostnames = [ (cluster.methods.mkAppHostname "argocd") ];
            rules = [
              {
                matches = [
                  {
                    path = {
                      type = "PathPrefix";
                      value = "/";
                    };
                  }
                ];
                backendRefs = [
                  {
                    group = "";
                    kind = "Service";
                    name = "argocd-server";
                    port = 443;
                    weight = 1;
                  }
                ];
              }
            ];
          };

          resources.grpcRoutes.argocd-grpc.spec = {
            parentRefs = [
              {
                group = "gateway.networking.k8s.io";
                kind = "Gateway";
                name = "apps";
                namespace = "envoy-gateway-system";
                sectionName = "https";
              }
            ];
            hostnames = [ (cluster.methods.mkAppHostname "argocd") ];
            rules = [
              {
                # Without a match this ties with the HTTPRoute on /, which is listed first, so gRPC never got here.
                matches = [
                  {
                    headers = [
                      {
                        name = "Content-Type";
                        type = "RegularExpression";
                        value = "^application/grpc.*$";
                      }
                    ];
                  }
                ];
                backendRefs = [
                  {
                    group = "";
                    kind = "Service";
                    name = "argocd-server";
                    port = 443;
                    weight = 1;
                  }
                ];
              }
            ];
          };
        };
      };
    };
}
