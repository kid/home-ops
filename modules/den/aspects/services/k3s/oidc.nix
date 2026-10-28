# Log in to the API server with Kanidm (kubectl through kubelogin). Split out of k3s-server because only a
# host whose cluster runs Kanidm should include it. The values come from den.clusters.<name>.methods.kubeLogin,
# set in modules/den/aspects/kubernetes/apiserver/default.nix, like the Kanidm client itself.
# The username claim stays the default `sub`: users show up as `<issuer>#<Kanidm person UUID>`.
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
        # Kanidm signs ID tokens with ES256; kube-apiserver only accepts RS256 by default.
        "--kube-apiserver-arg=oidc-signing-algs=ES256"
      ];
    };
}
