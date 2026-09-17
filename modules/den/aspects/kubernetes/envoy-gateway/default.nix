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
            lib.optionalAttrs (cluster.name == "prd") {
              resources.pushSecrets.apps-tls.spec = {
                refreshInterval = "1h";
                secretStoreRefs = [
                  {
                    name = "openbao";
                    kind = "ClusterSecretStore";
                  }
                ];
                selector.secret.name = "apps-tls";
                data = [
                  {
                    match = {
                      secretKey = "tls.crt";
                      remoteRef = {
                        remoteKey = "apps-tls";
                        property = "tls.crt";
                      };
                    };
                  }
                  {
                    match = {
                      secretKey = "tls.key";
                      remoteRef = {
                        remoteKey = "apps-tls";
                        property = "tls.key";
                      };
                    };
                  }
                ];
              };

              resources.externalSecrets.apps-tls = {
                metadata.annotations."argocd.argoproj.io/sync-wave" = "-1";
                spec = {
                  secretStoreRef = {
                    name = "openbao";
                    kind = "ClusterSecretStore";
                  };
                  target = {
                    name = "apps-tls";
                    creationPolicy = "Merge";
                  };
                  data = [
                    {
                      secretKey = "tls.crt";
                      remoteRef = {
                        key = "apps-tls";
                        property = "tls.crt";
                      };
                    }
                    {
                      secretKey = "tls.key";
                      remoteRef = {
                        key = "apps-tls";
                        property = "tls.key";
                      };
                    }
                  ];
                };
              };
            }
          );
    };
}
