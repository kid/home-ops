# kubectl reaches the API server through the apps Gateway: its Envoy Service is a BGP-advertised
# LoadBalancer, and a TLS passthrough listener on 6443 hands the connection to the kubernetes Service, so
# kubectl sees the API server's own certificate. external-dns names it through the TLSRoute.
# The login side is modules/den/aspects/services/k3s/oidc.nix.
_: {
  den.aspects.kubernetes.apiserver.k8s-manifests =
    { cluster, ... }:
    let
      hostname = cluster.methods.mkAppHostname "kube";
    in
    {
      # Merged with the https listener in envoy-gateway/default.nix, which is shared with dev.
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

        # No typed TLSRoute in nixidy here.
        yamls = [
          (builtins.toJSON {
            apiVersion = "gateway.networking.k8s.io/v1";
            kind = "TLSRoute";
            metadata = {
              name = "kube-api";
              namespace = "default";
            };
            spec = {
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
          })
        ];

        # Group names carry the oidc: prefix set in the authentication config.
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
              name = "oidc:admins";
            }
          ];
        };
      };
    };
}
