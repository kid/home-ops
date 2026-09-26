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
      cluster,
      ...
    }:
    {
      applications.envoy-gateway = {
        namespace = "envoy-gateway-system";

        helm.releases.envoy-gateway = {
          chart = charts.envoyproxy.gateway-helm;
          values.crds.enabled = true;
        };

        resources.gatewayClasses.envoy.spec.controllerName =
          "gateway.envoyproxy.io/gatewayclass-controller";

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
