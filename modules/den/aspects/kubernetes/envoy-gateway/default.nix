# Envoy Gateway (https://gateway.envoyproxy.io/): the controller (replacing
# Cilium's own, see cilium/default.nix's envoy.enabled = false) and the
# shared "apps" Gateway cluster.domain apps attach HTTPRoutes to — one
# aspect, since neither is useful without the other in this repo.
{ config, ... }:
let
  mkAppHostname = clusterName: appName: "${appName}.${config.den.clusters.${clusterName}.domain}";
in
{
  den.clusters.prd.methods.mkAppHostname = mkAppHostname "prd";

  den.aspects.kubernetes.envoy-gateway.k8s-manifests =
    {
      charts,
      generators,
      cluster,
      ...
    }:
    {
      nixidy.applicationImports = [
        (generators.fromChartCRDModule {
          name = "envoy-gateway-client-traffic-policy";
          chart = charts.envoyproxy.gateway-helm;
          kindFilter = [ "ClientTrafficPolicy" ];
        })
        (generators.fromChartCRDModule {
          name = "envoy-gateway-envoy-proxy";
          chart = charts.envoyproxy.gateway-helm;
          kindFilter = [ "EnvoyProxy" ];
        })
      ];

      applications.envoy-gateway = {
        namespace = "envoy-gateway-system";

        helm.releases.envoy-gateway = {
          chart = charts.envoyproxy.gateway-helm;
          values.crds.enabled = true;
        };

        resources.gatewayClasses.envoy.spec = {
          controllerName = "gateway.envoyproxy.io/gatewayclass-controller";
          parametersRef = {
            group = "gateway.envoyproxy.io";
            kind = "EnvoyProxy";
            name = "apps";
            namespace = "envoy-gateway-system";
          };
        };

        # Pins the data-plane proxy Service's name, which Envoy Gateway
        # otherwise auto-generates at runtime — cloudflared/default.nix's
        # HTTPRoutes need a stable target to forward tunnel traffic to.
        resources.envoyProxies.apps.spec.provider = {
          type = "Kubernetes";
          kubernetes.envoyService.name = "envoy-gateway-apps";
        };

        resources.clientTrafficPolicies.apps.spec = {
          targetRefs = [
            {
              group = "gateway.networking.k8s.io";
              kind = "Gateway";
              name = "apps";
            }
          ];
          clientIPDetection.xForwardedFor.numTrustedHops = 1;
        };

        resources.gateways.apps.spec = {
          gatewayClassName = "envoy";
          listeners = [
            {
              name = "https";
              protocol = "HTTPS";
              port = 443;
              hostname = "*.${cluster.domain}";
              tls = {
                mode = "Terminate";
                certificateRefs = [
                  {
                    group = "";
                    kind = "Secret";
                    name = "apps-tls";
                  }
                ];
              };
              allowedRoutes.namespaces.from = "All";
            }
          ];
        };

        # Lets an app's own public HTTPRoute (cross-namespace, on the
        # "cloudflare-tunnel" Gateway) forward into this Service — Gateway API
        # requires explicit opt-in per source namespace for cross-namespace
        # backendRefs. Add a namespace here for every app that gets a
        # "<app>-public" HTTPRoute (see argocd/default.nix for the pattern).
        resources.referenceGrants.public-ingress.spec = {
          from = [
            {
              group = "gateway.networking.k8s.io";
              kind = "HTTPRoute";
              namespace = "argocd";
            }
          ];
          to = [
            {
              group = "";
              kind = "Service";
              name = "envoy-gateway-apps";
            }
          ];
        };

        # Issued once by cert-manager's own app, see cert-manager/default.nix.
        resources.externalSecrets.apps-tls.spec = {
          secretStoreRef = {
            name = "onepassword";
            kind = "ClusterSecretStore";
          };
          target = {
            name = "apps-tls";
            template.type = "kubernetes.io/tls";
          };
          dataFrom = [
            {
              extract = {
                key = "wildcard-tls";
                decodingStrategy = "Base64";
              };
            }
          ];
        };
      };
    };
}
