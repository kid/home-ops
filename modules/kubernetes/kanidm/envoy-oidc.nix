# Gates an app behind Kanidm with Envoy Gateway's native OIDC: one Kanidm client
# per app, only granted to `group`, and a SecurityPolicy on the app's HTTPRoute,
# or only on its rule `sectionName` when the route has rules that must stay open.
# Returns an application module, for that application's `imports`.
#
# The endpoints are explicit: otherwise Envoy Gateway fetches discovery on every
# config recompute and serves a 500 when Kanidm is unreachable.
{ lib, ... }:
let
  mkOidcAuth =
    kanidm:
    {
      name,
      httpRouteName,
      sectionName ? null,
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
      # kaniop's webhook admits the client.
      flux.dependsOn = [ "kaniop" ];

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
          (
            {
              group = "gateway.networking.k8s.io";
              kind = "HTTPRoute";
              name = httpRouteName;
            }
            // lib.optionalAttrs (sectionName != null) { inherit sectionName; }
          )
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
  den.clusterMethods.mkOidcAuth = cluster: mkOidcAuth cluster.methods.kanidm;
}
