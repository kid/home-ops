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
      ];

      applications.envoy-gateway = {
        namespace = "envoy-gateway-system";

        resources.ciliumNetworkPolicies =
          with cluster.methods.netpol;
          let
            proxy = {
              "app.kubernetes.io/name" = "envoy";
            };
          in
          {
            envoy-gateway = mkPolicy { control-plane = "envoy-gateway"; } {
              ingress = [
                (fromPods proxy [ 18000 ])
                (webhookIngress 9443)
              ];
              egress = [ apiserverEgress ];
            };
            envoy-gateway-certgen = mkPolicy { app = "certgen"; } {
              egress = [ apiserverEgress ];
            };
            envoy-proxy = mkPolicy proxy {
              ingress = [
                # Envoy Gateway remaps privileged listener ports to 10000 + port.
                {
                  fromEntities = [ "world" ];
                  toPorts = tcp [
                    10443
                    6443
                  ];
                }
              ];
              egress = [ clusterEgress ];
            };
          };

        helm.releases.envoy-gateway = {
          chart = charts.envoyproxy.gateway-helm;
          values.crds.enabled = true;
        };

        resources.gatewayClasses.envoy.spec.controllerName =
          "gateway.envoyproxy.io/gatewayclass-controller";

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
