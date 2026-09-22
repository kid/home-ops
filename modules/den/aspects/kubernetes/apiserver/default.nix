# kubectl reaches the API server through the apps Gateway: its Envoy Service is a BGP-advertised
# LoadBalancer, and a TLS passthrough listener on 6443 hands the connection to the kubernetes Service, so
# kubectl sees the API server's own certificate. external-dns names it through the TLSRoute.
# The login side is modules/den/aspects/services/k3s/oidc.nix.
{ config, ... }:
let
  mkAppHostname = config.den.clusters.prd.methods.mkAppHostname;
in
{
  # Shared by the Authelia client, the k3s API server flags and modules/flake/docs.nix, so they cannot drift.
  den.clusters.prd.methods.kubeLogin = {
    clientId = "kube_login";
    group = "admins";
    issuerUrl = "https://${mkAppHostname "auth"}";
    server = mkAppHostname "kube";
  };

  den.aspects.kubernetes.apiserver.k8s-manifests =
    { cluster, ... }:
    let
      hostname = cluster.methods.kubeLogin.server;
    in
    {
      # Merged with the https listener in envoy-gateway/default.nix.
      applications.envoy-gateway.resources.gateways.apps.spec.listeners = [
        {
          name = "kube-api";
          protocol = "TLS";
          port = 6443;
          inherit hostname;
          tls.mode = "Passthrough";
          allowedRoutes = {
            namespaces.from = "All";
            kinds = [ { kind = "TLSRoute"; } ];
          };
        }
      ];

      applications.apiserver = {
        # Where the kubernetes Service lives, so the backendRef needs no ReferenceGrant.
        namespace = "default";

        resources.tlsRoutes.kube-api.spec = {
          parentRefs = [
            {
              name = "apps";
              namespace = "envoy-gateway-system";
              sectionName = "kube-api";
            }
          ];
          hostnames = [ hostname ];
          rules = [
            {
              backendRefs = [
                {
                  name = "kubernetes";
                  port = 443;
                }
              ];
            }
          ];
        };

        # kube-apiserver adds no groups prefix, so this is the group name as Authelia sends it.
        resources.clusterRoleBindings.oidc-admins = {
          roleRef = {
            apiGroup = "rbac.authorization.k8s.io";
            kind = "ClusterRole";
            name = "cluster-admin";
          };
          subjects = [
            {
              apiGroup = "rbac.authorization.k8s.io";
              kind = "Group";
              name = cluster.methods.kubeLogin.group;
            }
          ];
        };
      };
    };
}
