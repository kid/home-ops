# Log in through Kanidm. Separate from default.nix so that file doesn't depend on Kanidm.
_: {
  den.aspects.kubernetes.grafana-oidc.k8s-manifests =
    { cluster, ... }:
    let
      inherit (cluster.methods) kanidm;
      clientId = "grafana";
      origin = "https://${cluster.methods.mkAppHostname "grafana"}";
    in
    {
      applications.grafana-operator = {
        flux.dependsOn = [ "kaniop" ];

        resources.grafanas.grafana.spec = {
          config = {
            # auth.basic stays enabled: the operator uses it to reconcile dashboards and datasources.
            auth = {
              disable_login_form = "true";
              # Links a login to an existing user with the same email. Safe: Kanidm
              # is the only OAuth provider and emails are set by admins.
              oauth_allow_insecure_email_lookup = "true";
            };

            # client_secret comes from GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET below.
            "auth.generic_oauth" = {
              enabled = "true";
              name = "Kanidm";
              client_id = clientId;
              auth_url = "${kanidm.origin}/ui/oauth2";
              token_url = "${kanidm.origin}/oauth2/token";
              api_url = "${kanidm.issuer clientId}/userinfo";
              use_pkce = "true";
              # groups_name puts plain group names in the groups claim.
              scopes = "openid profile email groups_name";
              role_attribute_path = "contains(groups[*], 'admins') && 'Admin' || 'Viewer'";
            };
          };

          deployment.spec.template.spec.containers = [
            {
              name = "grafana";
              env = [
                {
                  name = "GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET";
                  valueFrom.secretKeyRef = {
                    name = "${clientId}-kanidm-oauth2-credentials";
                    key = "clientSecret";
                  };
                }
              ];
            }
          ];
        };

        resources.kanidmOAuth2Clients.${clientId} = {
          spec = {
            kanidmRef = kanidm.ref;
            displayname = "Grafana";
            inherit origin;
            redirectUrl = [ "${origin}/login/generic_oauth" ];
            # Grafana logins use the short name, not the user@domain SPN.
            preferShortUsername = true;
            scopeMap = [
              {
                group = "admins";
                scopes = [
                  "openid"
                  "profile"
                  "email"
                  "groups_name"
                ];
              }
            ];
            secretKeyAliases.clientSecret = [ "clientSecret" ];
          };
        };
      };
    };
}
