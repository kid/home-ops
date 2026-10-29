# Gates an app with no login of its own behind Kanidm, with Envoy Gateway's
# native OIDC (https://gateway.envoyproxy.io/docs/tasks/security/oidc/): one
# confidential Kanidm OAuth2 client per app, which only members of `group`
# may authorize, and a SecurityPolicy on the app's HTTPRoute.
#
# Returns an application module, for that application's `imports`: both
# objects then land in the HTTPRoute's namespace, where kaniop also writes
# the client's Secret.
#
# Both endpoints are set explicitly: with either missing, Envoy Gateway
# fetches the issuer's discovery document on every config recompute and
# turns the route into a 500 when that fails, e.g. while Kanidm restarts.
# They are the same for every Kanidm client. Only the proxy reaches Kanidm,
# for the token exchange, through the apps Gateway.
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
          provider = {
            issuer = kanidm.issuer name;
            authorizationEndpoint = "${kanidm.origin}/ui/oauth2";
            tokenEndpoint = "${kanidm.origin}/oauth2/token";
          };
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
