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
                # The secret-init init container creates the redis password Secret.
                egress = [ apiserverEgress ];
              };
            };

          kustomize.applications.argocd = {
            namespace = "argocd";
            kustomization = {
              src = pkgs.fetchFromGitHub {
                owner = "argoproj";
                repo = "argo-cd";
                # renovate: datasource=github-releases depName=argoproj/argo-cd
                rev = "v3.5.6";
                hash = "sha256-Gv/7K3eU80ncOyHq/OPKneQTOVcsuYkJ2F9YiqNOdEU=";
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
          # previous app's pods are still starting. A new Application also
          # shows Healthy for a moment before its first sync, so it stays
          # Progressing until it is Synced or has synced once (status.history).
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
            if hs.status == "Healthy" and (obj.status.history == nil or #obj.status.history == 0)
                and (obj.status.sync == nil or obj.status.sync.status ~= "Synced") then
              hs.status = "Progressing"
              hs.message = "Waiting for the first successful sync"
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

          # ArgoCD's built-in check keeps a GrafanaDashboard Progressing until
          # grafana-operator sets its status. An app in an earlier wave than
          # grafana-operator (kopiur) then never gets healthy, and the apps
          # Application never reaches grafana-operator's wave. A False
          # condition is still Degraded.
          resources.configMaps.argocd-cm.data."resource.customizations.health.grafana.integreatly.org_GrafanaDashboard" =
            ''
              hs = {}
              hs.status = "Healthy"
              hs.message = "Not reconciled by grafana-operator yet"
              if obj.status ~= nil and obj.status.conditions ~= nil then
                for i, condition in ipairs(obj.status.conditions) do
                  if condition.status == "False" then
                    hs.status = "Degraded"
                    hs.message = (condition.reason or "") .. ": " .. (condition.message or "")
                    return hs
                  end
                  if condition.status == "True" then
                    hs.message = condition.message or ""
                  end
                end
              end
              return hs
            '';

          # Replaces argocd-server's ephemeral self-signed cert with one off the cluster CA.
          # argocd-server only reloads its settings, this cert included, when a
          # Secret labeled part-of=argocd changes: without the label it keeps
          # serving the cert it started with after cert-manager renews it.
          resources.certificates.argocd-server-tls.spec = {
            secretName = "argocd-server-tls";
            secretTemplate.labels."app.kubernetes.io/part-of" = "argocd";
            dnsNames = [
              "argocd-server"
              "argocd-server.argocd.svc.cluster.local"
            ];
            issuerRef = {
              name = "cluster-ca";
              kind = "ClusterIssuer";
              group = "cert-manager.io";
            };
          };

          # cluster-ca ConfigMap comes from trust-manager/default.nix's Bundle.
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
                  name = "cluster-ca";
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
