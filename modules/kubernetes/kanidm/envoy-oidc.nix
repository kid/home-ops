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
        # Kanidm's 16h default ends a login after a night without a request, and
        # Envoy then redirects to Kanidm. 7 days matches idm_all_accounts'
        # auth-expiry (kanidm/default.nix), which still ends every OAuth2 session
        # with the browser session it came from, until Kanidm supports
        # offline_access (https://github.com/kanidm/kanidm/issues/4034).
        refreshTokenExpiry = 7 * 24 * 3600;
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
          # Only a page navigation can follow the redirect to Kanidm. Every
          # redirect sets two per-flow cookies that live 10 minutes, so a
          # polling SPA with an expired session (renovate) piled them past
          # Firefox's 180-cookie limit for kidibox.net, which then evicted
          # Kanidm's session cookie and other apps' OIDC cookies. A fetch,
          # subresource or websocket gets a 401 instead.
          denyRedirect.headers = [
            {
              name = "Sec-Fetch-Mode";
              type = "RegularExpression";
              value = "cors|no-cors|same-origin|websocket";
            }
          ];
        };
      };
    };
in
{
  den.clusterMethods.mkOidcAuth = cluster: mkOidcAuth cluster.methods.kanidm;
}
