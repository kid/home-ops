# Gates an app with no login of its own behind Kanidm, with Envoy Gateway's
# native OIDC (https://gateway.envoyproxy.io/docs/tasks/security/oidc/): one
# confidential Kanidm OAuth2 client per app, which only members of `group`
# may authorize, and a SecurityPolicy on the app's HTTPRoute.
#
# Returns an application module, for that application's `imports`: both
# objects then land in the HTTPRoute's namespace, where kaniop also writes
# the client's Secret.
#
# Envoy reaches Kanidm at its origin, through the apps Gateway: the
# controller to discover the endpoints (envoy-gateway/default.nix gives it
# netpol.gatewayEgress), the proxy for the token exchange. A
# provider.backendRefs to the Kanidm Service would not avoid the first: the
# controller dials the issuer hostname either way, and would then check the
# Gateway's certificate against the BackendTLSPolicy's cluster-ca.
{ config, ... }:
let
  inherit (config.den.clusters.prd.methods) kanidm;
  mkOidcAuth =
    {
      name,
      httpRouteName,
      hostname,
      group,
    }:
    let
      origin = "https://${hostname}";
      scopes = [
        "openid"
        "profile"
        "email"
      ];
    in
    {
      resources.kanidmOAuth2Clients.${name}.spec = {
        kanidmRef = kanidm.ref;
        displayname = name;
        inherit origin;
        redirectUrl = [ "${origin}/oauth2/callback" ];
        # Non-members get no scope, so Kanidm refuses their authorization.
        scopeMap = [ { inherit group scopes; } ];
        disableConsentPrompt = true;
        # The key Envoy Gateway reads the client secret from.
        secretKeyAliases.clientSecret = [ "client-secret" ];
      };

      resources.securityPolicies.${name}.spec = {
        targetRefs = [
          {
            group = "gateway.networking.k8s.io";
            kind = "HTTPRoute";
            name = httpRouteName;
          }
        ];
        oidc = {
          provider.issuer = kanidm.issuer name;
          clientID = name;
          clientSecret.name = "${name}-kanidm-oauth2-credentials";
          inherit scopes;
          redirectURL = "${origin}/oauth2/callback";
          # Kanidm has no end-session endpoint: this only clears Envoy's cookies.
          logoutPath = "/oauth2/logout";
        };
      };
    };
in
{
  den.clusters.prd.methods.mkOidcAuth = mkOidcAuth;
}
