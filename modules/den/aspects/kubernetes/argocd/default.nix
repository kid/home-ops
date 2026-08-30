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
          createNamespace = true;

          kustomize.applications.argocd = {
            namespace = "argocd";
            kustomization = {
              src = pkgs.fetchFromGitHub {
                owner = "argoproj";
                repo = "argo-cd";
                # renovate: datasource=github-releases depName=argoproj/argo-cd
                rev = "v3.4.4";
                hash = "sha256-I3udVhmPpOA2Lf1mkJqG+d+mGpfM16HIKBkEnTiAw0c=";
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

          # TLS terminates at the shared apps-gateway Gateway (see
          # modules/den/aspects/kubernetes/apps-gateway), so argocd-server
          # must not also terminate TLS itself.
          resources.configMaps.argocd-cmd-params-cm.data."server.insecure" = "true";

          # argocd-server multiplexes grpc-web/HTTP (UI) and native gRPC
          # (CLI) on the same container port, but Gateway API needs them
          # split across an HTTPRoute and a GRPCRoute, each pointed at its
          # own Service port — the "https" port is marked h2c so Cilium's
          # Envoy speaks HTTP/2 cleartext to the backend for gRPC.
          # mkForce replaces rather than merges: nixidy's resource-override
          # otherwise concatenates list-typed options like spec.ports.
          resources.services.argocd-server.spec.ports = lib.mkForce [
            {
              name = "http";
              port = 80;
              targetPort = 8080;
            }
            {
              name = "https";
              port = 443;
              targetPort = 8080;
              appProtocol = "kubernetes.io/h2c";
            }
          ];

          resources.httpRoutes.argocd.spec = {
            parentRefs = [
              {
                name = "apps";
                namespace = "gateway";
                sectionName = "https";
              }
            ];
            hostnames = [ (cluster.methods.mkAppHostname "argocd") ];
            rules = [
              {
                backendRefs = [
                  {
                    name = "argocd-server";
                    port = 80;
                  }
                ];
              }
            ];
          };

          resources.grpcRoutes.argocd-grpc.spec = {
            parentRefs = [
              {
                name = "apps";
                namespace = "gateway";
                sectionName = "https";
              }
            ];
            hostnames = [ (cluster.methods.mkAppHostname "argocd") ];
            rules = [
              {
                backendRefs = [
                  {
                    name = "argocd-server";
                    port = 443;
                  }
                ];
              }
            ];
          };
        };
      };
    };
}
