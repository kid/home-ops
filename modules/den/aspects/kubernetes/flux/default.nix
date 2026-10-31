# Flux, installed and upgraded by the Flux Operator
# (https://fluxoperator.dev). The operator runs from its Helm chart; the
# FluxInstance below makes it deploy the Flux controllers and the root sync:
# a GitRepository plus a Kustomization named flux-system that applies
# manifests/<cluster>/apps, where nixidy-defaults.nix renders one Flux
# Kustomization per app. modules/den/aspects/services/k3s/bootstrap.nix
# applies this app once on a new cluster; from then on Flux manages it too.
#
# The operator also serves the Flux web UI, which logs in through Kanidm and
# acts as the user's own name and groups. Its config, with the client secret
# Flux substitutes in at apply time, lives in the flux-web app's Secret.
_: {
  den.aspects.kubernetes.flux.k8s-manifests =
    {
      charts,
      generators,
      cluster,
      config,
      ...
    }:
    let
      webPort = 9080;
      hostname = cluster.methods.mkAppHostname "flux";
      origin = "https://${hostname}";
      clientId = "flux-web";
      configSecret = "flux-web-config";
      inherit (cluster.methods) kanidm kubeLogin;
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
            web = {
              # The CiliumNetworkPolicy above replaces it.
              networkPolicy.create = false;
              # Watched, so the operator picks it up once the flux-web app creates it.
              configSecretName = configSecret;
            };
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
          sync = with config.nixidy.target; {
            kind = "GitRepository";
            url = repository;
            ref = "refs/heads/${branch}";
            path = "${rootPath}/${config.nixidy.appOfApps.name}";
          };
        };
      };

      # The UI's Kanidm client, separate so flux-web can wait for its credentials Secret.
      applications.flux-web-client = {
        namespace = "flux-system";
        flux.dependsOn = [ "kaniop" ];

        resources.kanidmOAuth2Clients.${clientId}.spec = {
          kanidmRef = kanidm.ref;
          displayname = "Flux";
          inherit origin;
          redirectUrl = [ "${origin}/oauth2/callback" ];
          preferShortUsername = true;
          # The group kubectl's OIDC login is bound to cluster-admin through
          # (apiserver/default.nix). The UI impersonates it, so it is the
          # UI's RBAC as well.
          scopeMap = [
            {
              inherit (kubeLogin) group;
              scopes = [
                "openid"
                "profile"
                "email"
                "groups_name"
              ];
            }
          ];
        };
      };

      # Separate from flux-operator so the operator never waits on Kanidm.
      applications.flux-web = {
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
                # groups_name puts plain group names in the groups claim.
                scopes = [
                  "openid"
                  "profile"
                  "email"
                  "groups_name"
                ];
                autoLogin = true;
                impersonation = {
                  username = "claims.preferred_username";
                  groups = "claims.groups";
                };
              };
            };
            # No metrics-server here: collection only logs errors.
            metrics.disabled = true;
          };
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
    };
}
