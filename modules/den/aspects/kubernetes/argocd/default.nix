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

          resources.ciliumNetworkPolicies =
            with cluster.methods.netpol;
            let
              app = name: { "app.kubernetes.io/name" = "argocd-${name}"; };
              redis = toPods (app "redis") [ 6379 ];
              repoServer = toPods (app "repo-server") [ 8081 ];
              authelia = fqdnEgress [ (cluster.methods.mkAppHostname "auth") ] [ 443 ];
            in
            {
              argocd-application-controller = mkPolicy (app "application-controller") {
                egress = [
                  apiserverEgress
                  redis
                  repoServer
                ];
              };
              argocd-server = mkPolicy (app "server") {
                ingress = [
                  (gatewayIngress 8080)
                  (tunnelIngress 8080)
                ];
                egress = [
                  apiserverEgress
                  redis
                  repoServer
                  (toPods (app "dex-server") [
                    5556
                    5557
                  ])
                  authelia
                ];
              };
              argocd-repo-server = mkPolicy (app "repo-server") {
                ingress = map (name: fromPods (app name) [ 8081 ]) [
                  "server"
                  "application-controller"
                  "applicationset-controller"
                  "notifications-controller"
                ];
                egress = [
                  redis
                  (fqdnEgress [ "github.com" ] [ 443 ])
                ];
              };
              argocd-applicationset-controller = mkPolicy (app "applicationset-controller") {
                egress = [
                  apiserverEgress
                  repoServer
                ];
              };
              argocd-dex-server = mkPolicy (app "dex-server") {
                ingress = [
                  (fromPods (app "server") [
                    5556
                    5557
                  ])
                ];
                egress = [
                  apiserverEgress
                  authelia
                ];
              };
              argocd-notifications-controller = mkPolicy (app "notifications-controller") {
                egress = [
                  apiserverEgress
                  repoServer
                ];
              };
              argocd-redis = mkPolicy (app "redis") {
                ingress = map (name: fromPods (app name) [ 6379 ]) [
                  "server"
                  "repo-server"
                  "application-controller"
                ];
              };
            };

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
            # Upstream's NetworkPolicies would widen the CiliumNetworkPolicies above.
            transformer = builtins.filter (o: o.kind != "NetworkPolicy");
          };

          resources.statefulSets.argocd-application-controller.spec.template.spec.containers.argocd-application-controller.resources =
            {
              requests = {
                cpu = "50m";
                memory = "768Mi";
              };
              limits.memory = "2560Mi";
            };

          resources.deployments = {
            argocd-applicationset-controller.spec.template.spec.containers.argocd-applicationset-controller.resources =
              {
                requests = {
                  cpu = "10m";
                  memory = "64Mi";
                };
                limits.memory = "192Mi";
              };
            argocd-notifications-controller.spec.template.spec.containers.argocd-notifications-controller.resources =
              {
                requests = {
                  cpu = "10m";
                  memory = "64Mi";
                };
                limits.memory = "192Mi";
              };
            argocd-repo-server.spec.template.spec.initContainers.copyutil.resources.requests = {
              cpu = "10m";
              memory = "32Mi";
            };
            argocd-dex-server.spec.template.spec.initContainers.copyutil.resources.requests = {
              cpu = "10m";
              memory = "32Mi";
            };
            argocd-redis.spec.template.spec.initContainers.secret-init.resources.requests = {
              cpu = "10m";
              memory = "32Mi";
            };
            argocd-repo-server.spec.template.spec.containers.argocd-repo-server.resources = {
              requests = {
                cpu = "10m";
                memory = "128Mi";
              };
              limits.memory = "384Mi";
            };
            argocd-server.spec.template.spec.containers.argocd-server.resources = {
              requests = {
                cpu = "10m";
                memory = "64Mi";
              };
              limits.memory = "256Mi";
            };
            argocd-dex-server.spec.template.spec.containers.dex.resources = {
              requests = {
                cpu = "10m";
                memory = "128Mi";
              };
              limits.memory = "256Mi";
            };
            argocd-redis.spec.template.spec.containers.redis.resources = {
              requests = {
                cpu = "10m";
                memory = "32Mi";
              };
              limits.memory = "64Mi";
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

          resources.httpRoutes.argocd-webhook.metadata.labels."home-ops.dev/public-dns" = "true";
          resources.httpRoutes.argocd-webhook.spec = {
            parentRefs = [
              {
                group = "gateway.networking.k8s.io";
                kind = "Gateway";
                name = "cloudflare-tunnel";
                namespace = "cloudflare-tunnel-system";
                sectionName = "http";
              }
            ];
            hostnames = [ (cluster.methods.mkAppHostname "argo-webhook") ];
            rules = [
              {
                matches = [
                  {
                    path = {
                      type = "PathPrefix";
                      value = "/api/webhook";
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

          resources.externalSecrets.argocd-github-webhook.spec = {
            secretStoreRef = {
              name = "onepassword";
              kind = "ClusterSecretStore";
            };
            target = {
              name = "argocd-secret";
              creationPolicy = "Merge";
              template.data."webhook.github.secret" = "{{ .githubWebhookSecret }}";
            };
            data = [
              {
                secretKey = "githubWebhookSecret";
                remoteRef.key = "argocd/secrets/github-webhook-secret";
              }
            ];
          };
        };
      };
    };
}
