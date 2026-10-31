# Log in to the API server with Kanidm (kubectl through kubelogin), using
# den.clusters.<name>.methods.kubeLogin from kubernetes/apiserver/default.nix.
{ config, ... }:
let
  clusters = config.den.clusters or { };
in
{
  den.aspects.k3s-oidc.nixos =
    { host, ... }:
    let
      login = clusters.${host.k3s.clusterName or "prd"}.methods.kubeLogin;
    in
    {
      services.k3s.extraFlags = [
        # Adds the load balancer name from kubernetes/apiserver/default.nix to the serving certificate.
        "--tls-san=${login.server}"
        "--kube-apiserver-arg=oidc-issuer-url=${login.issuerUrl}"
        "--kube-apiserver-arg=oidc-client-id=${login.clientId}"
        "--kube-apiserver-arg=oidc-groups-claim=groups"
        # Without these the username is "<issuer>#<sub>", an opaque UUID. The prefix keeps OIDC
        # names apart from built-in ones (system:*); RBAC binds the group, not the user.
        "--kube-apiserver-arg=oidc-username-claim=preferred_username"
        "--kube-apiserver-arg=oidc-username-prefix=oidc:"
        # Kanidm signs ID tokens with ES256; kube-apiserver only accepts RS256 by default.
        "--kube-apiserver-arg=oidc-signing-algs=ES256"
      ];
    };
}
