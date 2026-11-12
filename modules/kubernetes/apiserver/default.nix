# kubectl reaches the API server on its own LoadBalancer IP, BGP-advertised by Cilium. k3s runs the
# API server in its own process, with no pod a Service could select: a hostNetwork DaemonSet on the
# control-plane nodes stands in for it. Its pod IP is the node's, so the Service sends 6443 to that
# node's API server, and its readiness probe asks that API server's /readyz. With
# externalTrafficPolicy Local, only nodes whose probe passes advertise the IP. A node whose k3s
# stops also stops its kubelet and probes: it drops out once the node controller marks it NotReady.
# external-dns names it through the Service annotation. The kubernetes Service itself can't be a
# LoadBalancer: the API server reconciles it back. The login side is modules/nixos/services/k3s/oidc.nix.
_:
let
  clientId = "kube_login";
  name = "kube-api";
  labels."app.kubernetes.io/name" = name;
  # renovate: datasource=docker depName=docker.io/curlimages/curl
  tag = "8.23.0@sha256:3fb7e13e5d179a845c97d78204f3f1064d1907037f26a3ebf91710571151fd93";
in
{
  # Shared by the Kanidm client below, the k3s API server flags and modules/flake/kube-login.nix.
  # Every cluster has it: the last two check cluster.includesAspect for this aspect first.
  den.clusterMethods.kubeLogin =
    { methods, ... }:
    {
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
      applications.apiserver = {
        # Next to the kubernetes Service it stands in for.
        namespace = "default";
        # kaniop's webhook admits the kube-login client.
        flux.dependsOn = [ "kaniop" ];

        resources.services.${name} = {
          # external-dns 0.23 dropped the legacy external-dns.alpha.kubernetes.io/ prefix.
          metadata.annotations."external-dns.kubernetes.io/hostname" = hostname;
          spec = {
            type = "LoadBalancer";
            externalTrafficPolicy = "Local";
            selector = labels;
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

        resources.daemonSets.${name}.spec = {
          selector.matchLabels = labels;
          template = {
            metadata = { inherit labels; };
            spec = {
              hostNetwork = true;
              nodeSelector."node-role.kubernetes.io/control-plane" = "true";
              tolerations = [ { operator = "Exists"; } ];
              priorityClassName = "system-node-critical";
              # The default ServiceAccount's token: /readyz is open to any authenticated
              # user (system:public-info-viewer); k3s refuses anonymous requests.
              automountServiceAccountToken = true;
              securityContext = {
                runAsNonRoot = true;
                # The image's curl_user, by name only: runAsNonRoot needs a number.
                runAsUser = 100;
                runAsGroup = 101;
                seccompProfile.type = "RuntimeDefault";
              };
              containers.${name} = {
                image = "docker.io/curlimages/curl:${tag}";
                command = [
                  "sleep"
                  "infinity"
                ];
                readinessProbe = {
                  exec.command = [
                    "sh"
                    "-c"
                    ''curl -fsk --max-time 2 -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" https://127.0.0.1:6443/readyz''
                  ];
                  periodSeconds = 5;
                  timeoutSeconds = 3;
                  failureThreshold = 2;
                };
                resources = {
                  requests = {
                    cpu = "5m";
                    memory = "8Mi";
                  };
                  limits.memory = "32Mi";
                };
                securityContext = {
                  allowPrivilegeEscalation = false;
                  readOnlyRootFilesystem = true;
                  capabilities.drop = [ "ALL" ];
                };
              };
            };
          };
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
