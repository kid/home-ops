# Shared Gateway API entry point for cluster.domain apps — wildcard
# Certificate + Gateway once, HTTPRoute per app after.
{ config, ... }:
{
  den.clusters.prd.methods.mkAppHostname = name: "${name}.${config.den.clusters.prd.domain}";

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
            name = "letsencrypt-prod";
            kind = "ClusterIssuer";
            group = "cert-manager.io";
          };
        };

        resources.gateways.apps.spec = {
          gatewayClassName = "cilium";
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
