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
    { charts, cluster, ... }:
    {
      applications.envoy-gateway = {
        namespace = "envoy-gateway-system";
        createNamespace = true;

        helm.releases.envoy-gateway = {
          chart = charts.envoyproxy.gateway-helm;
          values = {
            # Gateway API CRDs are installed separately (gateway-api-crds.nix,
            # upstream standard channel) — the chart's own bundled copy
            # defaults to the experimental channel and would conflict.
            crds.enabled = false;
          };
        };

        # The chart doesn't create a GatewayClass itself (unlike Cilium's
        # gatewayClass.create shortcut) — gatewayclasses isn't one of
        # gateway-api-crds.nix's typed nixidy imports, so this goes through
        # the same raw-YAML escape hatch sops-operator's mkSopsSecret uses.
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
      };
    };
}
