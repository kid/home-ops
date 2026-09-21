# Log in to the API server with Authelia (kubectl through kubelogin), as in Authelia's kubelogin page
# (integration/openid-connect/clients/kubelogin). Split out of k3s-server because only a host whose
# cluster runs Authelia should include it. The values come from den.clusters.<name>.methods.kubeLogin,
# set in modules/den/aspects/kubernetes/apiserver/default.nix, like the Authelia client itself.
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
      ];
    };
}
