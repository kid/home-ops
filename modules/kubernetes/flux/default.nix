# Flux, installed and upgraded by the Flux Operator
# (https://fluxoperator.dev). The operator runs from its Helm chart; the
# FluxInstance below makes it deploy the Flux controllers and the root sync:
# a GitRepository plus a Kustomization named flux-system that applies
# manifests/<cluster>/apps, where nixidy-defaults.nix renders one Flux
# Kustomization per app. modules/nixos/services/k3s/bootstrap.nix
# applies this app once on a new cluster; from then on Flux manages it too.
#
# The operator also serves the Flux web UI, which logs in through Kanidm and
# acts as the user's own name in a single read-only group: no actions, and
# none of the user's own RBAC. Its config, with the client secret Flux
# substitutes in at apply time, lives in the flux-web app's Secret. A cluster
# without Kanidm runs no web UI.
{ den, ... }:
{
  den.aspects.kubernetes.flux.k8s-manifests =
    {
      charts,
      generators,
      cluster,
      config,
      lib,
      ...
    }:
    let
      webPort = 9080;
      hostname = cluster.methods.mkAppHostname "flux";
      origin = "https://${hostname}";
      clientId = "flux-web";
      configSecret = "flux-web-config";
      # The only group the UI acts as, bound to the operator's read-only flux-web-user role.
      readOnlyGroup = "flux-web-readonly";
      inherit (cluster.methods) kanidm kubeLogin;
      webUi = cluster.includesAspect den.aspects.kubernetes.kanidm;
      # The operator owns its namespace (kustomize.toolkit.fluxcd.io/ssa:
      # Ignore), so the apps sync skips the Namespace nixidy-defaults.nix
      # renders: its Pod Security labels reach it through a patch below.
      podSecurityLabels =
        config.applications.${config.nixidy.appOfApps.name}.resources.namespaces.flux-system.metadata.labels;
    in
    {
      nixidy.applicationImports = [
        (generators.fromChartCRDModule {
          name = "flux-operator";
          chart = charts.controlplaneio-fluxcd.flux-operator;
          kindFilter = [ "FluxInstance" ];
        })
      ];

      applications.flux-operator = {
        namespace = "flux-system";

        resources.ciliumNetworkPolicies =
          with cluster.methods.netpol;
          let
            controller = name: { app = name; };
          in
          {
            flux-operator = mkPolicy { "app.kubernetes.io/name" = "flux-operator"; } {
              ingress = [ (gatewayIngress webPort) ];
              egress = [
                apiserverEgress
                # Kanidm discovery, JWKS and token calls.
                gatewayEgress
              ];
            };
            source-controller = mkPolicy (controller "source-controller") {
              # Artifact downloads.
              ingress = [ (fromPods (controller "kustomize-controller") [ 9090 ]) ];
              egress = [
                apiserverEgress
                (fqdnEgress [ "github.com" ] [ 443 ])
                (toPods (controller "notification-controller") [ 9090 ])
              ];
            };
            kustomize-controller = mkPolicy (controller "kustomize-controller") {
              egress = [
                apiserverEgress
                (toPods (controller "source-controller") [ 9090 ])
                (toPods (controller "notification-controller") [ 9090 ])
              ];
            };
            notification-controller = mkPolicy (controller "notification-controller") {
              ingress = [
                # Events from the other controllers.
                (fromPods (controller "source-controller") [ 9090 ])
                (fromPods (controller "kustomize-controller") [ 9090 ])
                # GitHub's webhook, through the Cloudflare Tunnel proxy (webhook.nix).
                (tunnelIngress 9292)
              ];
              egress = [ apiserverEgress ];
            };
          };

        helm.releases.flux-operator = {
          chart = charts.controlplaneio-fluxcd.flux-operator;
          values = {
            # One replica, no leader election (lease renewals were most of
            # etcd's writes). Recreate keeps an update from running two at once.
            extraArgs = [ "--enable-leader-election=false" ];
            strategy.type = "Recreate";
            web = {
              # The CiliumNetworkPolicy above replaces it.
              networkPolicy.create = false;
            }
            // (
              if webUi then
                {
                  # Watched, so the operator picks it up once the flux-web app creates it.
                  configSecretName = configSecret;
                }
              else
                { enabled = false; }
            );
            resources = {
              requests = {
                cpu = "10m";
                memory = "64Mi";
              };
              # Peaked at 172Mi without the web UI.
              limits.memory = "512Mi";
            };
          };
        };

        resources.fluxInstances.flux.spec = {
          # The manifests come from the operator image, so the chart pin picks the Flux version.
          distribution = {
            version = "2.x";
            registry = "ghcr.io/fluxcd";
          };
          components = [
            "source-controller"
            "kustomize-controller"
            "notification-controller"
          ];
          cluster = {
            type = "kubernetes";
            size = "small";
            # Upstream's NetworkPolicies would widen the CiliumNetworkPolicies above.
            networkPolicy = false;
          };
          # The same for the controllers. The flag comes after the manifests'
          # own --enable-leader-election; source-controller is already Recreate.
          kustomize.patches = [
            {
              target = {
                kind = "Deployment";
                name = "(source-controller|kustomize-controller|notification-controller)";
              };
              patch = builtins.toJSON [
                {
                  op = "add";
                  path = "/spec/template/spec/containers/0/args/-";
                  value = "--enable-leader-election=false";
                }
                {
                  op = "replace";
                  path = "/spec/strategy";
                  value.type = "Recreate";
                }
              ];
            }
            {
              target = {
                kind = "Deployment";
                name = "kustomize-controller";
              };
              patch = builtins.toJSON [
                {
                  op = "replace";
                  path = "/spec/template/spec/containers/0/resources";
                  value = {
                    requests = {
                      cpu = "200m";
                      memory = "384Mi";
                    };
                    limits.memory = "512Mi";
                  };
                }
              ];
            }
            {
              target = {
                kind = "Namespace";
                name = "flux-system";
              };
              patch = builtins.toJSON {
                apiVersion = "v1";
                kind = "Namespace";
                metadata = {
                  name = "flux-system";
                  labels = podSecurityLabels;
                };
              };
            }
          ];
          sync = with config.nixidy.target; {
            kind = "GitRepository";
            url = repository;
            ref = "refs/heads/${branch}";
            path = "${rootPath}/${config.nixidy.appOfApps.name}";
          };
        };
      };

      # The UI's Kanidm client, separate so flux-web can wait for its credentials Secret.
      applications.flux-web-client = lib.mkIf webUi {
        namespace = "flux-system";
        flux.dependsOn = [ "kaniop" ];

        resources.kanidmOAuth2Clients.${clientId}.spec = {
          kanidmRef = kanidm.ref;
          displayname = "Flux";
          inherit origin;
          redirectUrl = [ "${origin}/oauth2/callback" ];
          preferShortUsername = true;
          # Only the group kubectl's OIDC login is bound to cluster-admin
          # through (apiserver/default.nix) may log in. The UI doesn't act as
          # it: see readOnlyGroup.
          scopeMap = [
            {
              inherit (kubeLogin) group;
              scopes = [
                "openid"
                "profile"
                "email"
              ];
            }
          ];
        };
      };

      # Separate from flux-operator so the operator never waits on Kanidm.
      applications.flux-web = lib.mkIf webUi {
        namespace = "flux-system";
        flux.dependsOn = [ "flux-web-client" ];
        # kaniop's credentials Secret for the client above.
        flux.substituteFrom = [ "${clientId}-kanidm-oauth2-credentials" ];

        resources.secrets.${configSecret}.stringData."config.yaml" = builtins.toJSON {
          apiVersion = "web.fluxcd.controlplane.io/v1";
          kind = "Config";
          spec = {
            baseURL = origin;
            authentication = {
              type = "OAuth2";
              oauth2 = {
                provider = "OIDC";
                clientID = clientId;
                clientSecret = "\${CLIENT_SECRET}";
                issuerURL = kanidm.issuer clientId;
                scopes = [
                  "openid"
                  "profile"
                  "email"
                ];
                autoLogin = true;
                impersonation = {
                  username = "claims.preferred_username";
                  groups = "['${readOnlyGroup}']";
                };
              };
            };
            # No metrics-server here: collection only logs errors.
            metrics.disabled = true;
          };
        };

        # Read-only on everything: the UI's action buttons are refused.
        resources.clusterRoleBindings.${readOnlyGroup} = {
          roleRef = {
            apiGroup = "rbac.authorization.k8s.io";
            kind = "ClusterRole";
            name = "flux-web-user";
          };
          subjects = [
            {
              apiGroup = "rbac.authorization.k8s.io";
              kind = "Group";
              name = readOnlyGroup;
            }
          ];
        };

        resources.httpRoutes.flux-web.spec = {
          parentRefs = [
            {
              group = "gateway.networking.k8s.io";
              kind = "Gateway";
              name = "apps";
              namespace = "envoy-gateway-system";
              sectionName = "https";
            }
          ];
          hostnames = [ hostname ];
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
                  name = "flux-operator";
                  port = webPort;
                  weight = 1;
                }
              ];
            }
          ];
        };
      };

      # Public through the tunnel: the UI and its MCP server keep their own Kanidm logins.
      applications.envoy-gateway = lib.mkIf webUi {
        resources.httpRoutes.flux-web-public = cluster.methods.mkGatewayTunnelRoute hostname;
      };
    };
}
