# kubectl reaches the API server through the apps Gateway: its Envoy Service is a BGP-advertised
# LoadBalancer, and a TLS passthrough listener on 6443 hands the connection to the kubernetes Service, so
# kubectl sees the API server's own certificate. external-dns names it through the TLSRoute.
# The login side is modules/den/aspects/services/k3s/oidc.nix.
{ config, ... }:
let
  inherit (config.den.clusters.prd) methods;
  clientId = "kube_login";
in
{
  # Shared by the Kanidm client below, the k3s API server flags and modules/flake/docs.nix.
  den.clusters.prd.methods.kubeLogin = {
    inherit clientId;
    group = "admins";
    issuerUrl = methods.kanidm.issuer clientId;
    server = methods.mkAppHostname "kube";
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
        # kaniop's webhook admits the kube-login client.
        flux.dependsOn = [ "kaniop" ];

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

        # Public: kubelogin runs locally and redirects to localhost. kanidmName because
        # Kubernetes names can't hold an underscore.
        resources.kanidmOAuth2Clients.kube-login.spec = {
          kanidmRef = cluster.methods.kanidm.ref;
          kanidmName = cluster.methods.kubeLogin.clientId;
          displayname = "Kubernetes";
          public = true;
          allowLocalhostRedirect = true;
          origin = "http://localhost:8000";
          redirectUrl = [
            "http://localhost:8000"
            "http://localhost:18000"
          ];
          # preferred_username is the short name (kube-apiserver's username claim, services/k3s/oidc.nix).
          preferShortUsername = true;
          scopeMap = [
            {
              group = cluster.methods.kubeLogin.group;
              scopes = [
                "openid"
                "profile"
                "email"
                "groups_name"
              ];
            }
          ];
        };

        # kube-apiserver adds no groups prefix, so this is the group name as Kanidm sends it.
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
