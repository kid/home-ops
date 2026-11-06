# kubectl reaches the API server on its own LoadBalancer IP, BGP-advertised by Cilium, through a
# selectorless kube-api Service whose EndpointSlice lists the servers from the k3s-nodes quirk.
# external-dns names it through the Service annotation. The kubernetes Service itself can't be a
# LoadBalancer: the API server reconciles it back. The login side is modules/nixos/services/k3s/oidc.nix.
{ config, ... }:
let
  inherit (config.den.clusters.prd) methods;
  clientId = "kube_login";
in
{
  # Shared by the Kanidm client below, the k3s API server flags and modules/flake/kube-login.nix.
  den.clusters.prd.methods.kubeLogin = {
    inherit clientId;
    group = "admins";
    issuerUrl = methods.kanidm.issuer clientId;
    server = methods.mkAppHostname "kube";
  };

  den.aspects.kubernetes.apiserver.k8s-manifests =
    {
      cluster,
      lib,
      k3s-nodes ? [ ],
      ...
    }:
    let
      hostname = cluster.methods.kubeLogin.server;
      servers =
        k3s-nodes
        |> lib.filter (n: n.address != null && n.role == "server")
        |> map (n: n.address)
        |> lib.sort lib.lessThan;
    in
    {
      applications.apiserver = {
        # Next to the kubernetes Service it stands in for.
        namespace = "default";
        # kaniop's webhook admits the kube-login client.
        flux.dependsOn = [ "kaniop" ];

        resources.services.kube-api = {
          metadata.annotations."external-dns.alpha.kubernetes.io/hostname" = hostname;
          spec = {
            type = "LoadBalancer";
            ports = [
              {
                name = "https";
                port = 6443;
                targetPort = 6443;
                protocol = "TCP";
              }
            ];
          };
        };

        # The kube-api Service has no selector: list the servers' addresses by hand.
        resources.endpointSlices.kube-api = {
          metadata.labels = {
            "kubernetes.io/service-name" = "kube-api";
            "endpointslice.kubernetes.io/managed-by" = "home-ops";
          };
          addressType = "IPv4";
          ports = [
            {
              name = "https";
              port = 6443;
              protocol = "TCP";
            }
          ];
          endpoints = map (address: {
            addresses = [ address ];
            conditions.ready = true;
          }) servers;
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
