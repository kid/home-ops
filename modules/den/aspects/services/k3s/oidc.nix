# Log in to the API server with Authelia (kubectl through kubelogin). Split out of k3s-server
# because only a host whose cluster runs Authelia should include it. The client is `kubernetes`,
# defined in modules/den/aspects/kubernetes/authelia/default.nix.
{ config, ... }:
let
  clusters = config.den.clusters or { };
in
{
  den.aspects.k3s-oidc.nixos =
    { host, pkgs, ... }:
    let
      cluster = clusters.${host.k3s.clusterName or "prd"};

      # The nix store keeps the file readable by k3s, and a change restarts it through the new flag path.
      authenticationConfig = pkgs.writeText "authentication-config.json" (
        builtins.toJSON {
          apiVersion = "apiserver.config.k8s.io/v1";
          kind = "AuthenticationConfiguration";
          jwt = [
            {
              issuer = {
                url = "https://${cluster.methods.mkAppHostname "auth"}";
                audiences = [ "kubernetes" ];
              };
              claimMappings = {
                username = {
                  claim = "preferred_username";
                  prefix = "oidc:";
                };
                groups = {
                  claim = "groups";
                  prefix = "oidc:";
                };
              };
            }
          ];
        }
      );
    in
    {
      services.k3s.extraFlags = [
        # The load balancer name from kubernetes/apiserver/default.nix.
        "--tls-san=${cluster.methods.mkAppHostname "kube"}"
        "--kube-apiserver-arg=authentication-config=${authenticationConfig}"
      ];
    };
}
