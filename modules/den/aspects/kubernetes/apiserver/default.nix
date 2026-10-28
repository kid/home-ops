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
  # Shared by the Kanidm client below, the k3s API server flags and modules/flake/docs.nix, so they cannot
  # drift. Kanidm gives each client its own issuer, so the issuer follows the client ID.
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

        # kubelogin is a public client: it runs on the user's machine and cannot keep a secret, so Kanidm
        # enforces PKCE and only public clients may redirect to localhost (kubelogin's ports 8000 and 18000).
        # The Kubernetes name cannot hold an underscore, hence kanidmName. Kanidm hands out refresh tokens
        # without an offline_access scope, and refuses scopes the map does not grant, so it is not listed.
        # groups_name makes the groups claim carry plain names (admins) rather than SPNs.
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
