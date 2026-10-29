# Log in through Kanidm (kubernetes/kanidm/default.nix): the "grafana"
# OAuth2 client is declared here, next to its only consumer. Separate from
# default.nix so that file doesn't hard-depend on Kanidm being present.
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
        resources.grafanas.grafana.spec = {
          config = {
            # No local login, so the form is hidden. If Kanidm is down, fix it through git and kubectl on the node.
            # auth.basic stays enabled — the operator itself authenticates to
            # Grafana's API with it to reconcile dashboards/datasources.
            auth = {
              disable_login_form = "true";
              # The existing user was created by the previous OIDC provider, whose `sub`
              # Kanidm doesn't share. Grafana looks an OAuth login up by
              # (module, sub) only; without this the first Kanidm login misses
              # it, then fails to create a second user with the same email.
              # With it, Grafana matches the existing user by email and rewrites
              # its stored sub, keeping its dashboards and preferences. Safe here:
              # Kanidm is the only OAuth provider and mail is set by admins
              # (the KanidmPersonAccount), not by the person.
              oauth_allow_insecure_email_lookup = "true";
            };

            "auth.generic_oauth" = {
              enabled = "true";
              name = "Kanidm";
              client_id = clientId;
              # client_secret comes in via GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET below —
              # Grafana maps GF_<SECTION>_<KEY> env vars onto config automatically.
              auth_url = "${kanidm.origin}/ui/oauth2";
              token_url = "${kanidm.origin}/oauth2/token";
              api_url = "${kanidm.issuer clientId}/userinfo";
              # Kanidm enforces PKCE on every client.
              use_pkce = "true";
              # groups_name: plain group names (`admins`) in the groups claim.
              scopes = "openid profile email groups_name";
              # Matches argocd/default.nix's own "admins" -> role:admin RBAC mapping.
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
                    # Written by kaniop for the client below.
                    name = "${clientId}-kanidm-oauth2-credentials";
                    key = "clientSecret";
                  };
                }
              ];
            }
          ];
        };

        resources.kanidmOAuth2Clients.${clientId} = {
          # Before the Grafana deployment that reads its Secret.
          metadata.annotations."argocd.argoproj.io/sync-wave" = "-1";
          spec = {
            kanidmRef = kanidm.ref;
            displayname = "Grafana";
            inherit origin;
            redirectUrl = [ "${origin}/login/generic_oauth" ];
            # preferred_username `kid` rather than the SPN `kid@idm.kidibox.net`,
            # which Grafana would otherwise write over the existing user's login.
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
