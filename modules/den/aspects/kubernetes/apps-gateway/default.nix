# Shared Gateway API entry point for cluster.domain apps — wildcard
# Certificate + Gateway once, HTTPRoute per app after.
{ config, ... }:
let
  mkAppHostname = clusterName: appName: "${appName}.${config.den.clusters.${clusterName}.domain}";
in
{
  # argocd/default.nix calls cluster.methods.mkAppHostname unconditionally
  # (for its own ingress hostname) regardless of whether this aspect's own
  # k8s-manifests content is included for that cluster — so every cluster
  # that includes argocd needs this method too, not just clusters that
  # actually deploy apps-gateway's Gateway/HTTPRoute objects. den has no
  # reverse "which clusters include me" lookup, and reading
  # config.den.clusters here to generalize it would self-reference
  # (infinite recursion), so list clusters explicitly.
  den.clusters.prd.methods.mkAppHostname = mkAppHostname "prd";
  den.clusters.dev.methods.mkAppHostname = mkAppHostname "dev";

  den.aspects.kubernetes.apps-gateway.k8s-manifests =
    { cluster, ... }:
    {
      applications.apps-gateway = {
        namespace = "gateway";
        createNamespace = true;

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
