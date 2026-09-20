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
  den.clusters.dev.methods.mkAppHostname = mkAppHostname "dev";

  den.aspects.kubernetes.envoy-gateway.k8s-manifests =
    {
      charts,
      cluster,
      lib,
      ...
    }:
    {
      applications.envoy-gateway =
        lib.recursiveUpdate
          {
            namespace = "envoy-gateway-system";
            createNamespace = true;

            helm.releases.envoy-gateway = {
              chart = charts.envoyproxy.gateway-helm;
              values.crds.enabled = true;
            };

            yamls = [
              (builtins.toJSON {
                apiVersion = "gateway.networking.k8s.io/v1";
                kind = "GatewayClass";
                metadata.name = "envoy";
                spec.controllerName = "gateway.envoyproxy.io/gatewayclass-controller";
              })
            ];

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
          }
          (
            if cluster.name == "prd" then
              {
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
              }
            else
              {
                resources.certificates.apps-tls.spec = {
                  secretName = "apps-tls";
                  dnsNames = [
                    "*.${cluster.domain}"
                    cluster.domain
                  ];
                  issuerRef = {
                    name = if cluster.letsencrypt.staging then "letsencrypt-staging" else "letsencrypt-prod";
                    kind = "ClusterIssuer";
                    group = "cert-manager.io";
                  };
                };
              }
          );
    };
}
