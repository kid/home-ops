# Gates an app behind Kanidm with Envoy Gateway's native OIDC: one Kanidm client
# per app, only granted to `group`, and a SecurityPolicy on the app's HTTPRoute.
# Returns an application module, for that application's `imports`.
#
# The endpoints are explicit: otherwise Envoy Gateway fetches discovery on every
# config recompute and serves a 500 when Kanidm is unreachable.
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
          provider = {
            issuer = kanidm.issuer name;
            authorizationEndpoint = "${kanidm.origin}/ui/oauth2";
            tokenEndpoint = "${kanidm.origin}/oauth2/token";
          };
          clientID = name;
          clientSecret.name = "${name}-kanidm-oauth2-credentials";
          inherit scopes;
          redirectURL = "${origin}/oauth2/callback";
          # Only clears Envoy's cookies: Kanidm has no end-session endpoint.
          logoutPath = "/oauth2/logout";
        };
      };
    };
in
{
  den.clusters.prd.methods.mkOidcAuth = mkOidcAuth;
}
