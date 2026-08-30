# Shared Gateway API entry point for cluster.domain apps: one Gateway with
# a wildcard HTTPS listener, backed by one wildcard cert-manager
# Certificate (letsencrypt-prod already does Cloudflare DNS-01, so a
# wildcard SAN works). Typed resources.gateways/certificates.* come from
# gateway-api-crds.nix's and cert-manager/default.nix's
# nixidy.applicationImports — merged in globally once those aspects are
# included, no need to re-import here.
#
# Future apps don't need their own Gateway or Certificate: just attach an
# HTTPRoute (or GRPCRoute) to this Gateway's "https" listener and call
# cluster.methods.mkAppHostname "name" for the hostname.
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

        # gatewayClassName "cilium": auto-provisioned by Cilium's own
        # Gateway API controller (cilium/default.nix's gatewayAPI.enabled),
        # not declared anywhere in this repo.
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
                certificateRefs = [ { name = "apps-tls"; } ];
              };
              # Lets HTTPRoutes/GRPCRoutes in other namespaces (e.g. argocd)
              # attach to this listener.
              allowedRoutes.namespaces.from = "All";
            }
          ];
        };
      };
    };
}
