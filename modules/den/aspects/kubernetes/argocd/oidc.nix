# Log in through Kanidm (kubernetes/kanidm/default.nix). Separate from default.nix so default.nix
# doesn't hard-depend on Kanidm being present.
_: {
  den.aspects.kubernetes.argocd-oidc.k8s-manifests =
    { cluster, ... }:
    let
      hostname = cluster.methods.mkAppHostname "argocd";
      clientId = "argocd";
    in
    {
      applications.argocd = {
        resources.configMaps.argocd-cm.data.url = "https://${hostname}";

        # No local login, so the form is hidden. If Kanidm is down, fix it through git and kubectl on the node.
        resources.configMaps.argocd-cm.data."admin.enabled" = "false";

        # One public client for the UI and `argocd login --sso`: Kanidm gives each client its own
        # issuer, so tokens from a separate cliClientID would fail argocd-server's issuer check.
        # argocd-server runs the UI's code flow with PKCE and no secret; the CLI falls back to
        # clientID and always sends PKCE.
        resources.configMaps.argocd-cm.data."oidc.config" = builtins.toJSON {
          name = "Kanidm";
          issuer = cluster.methods.kanidm.issuer clientId;
          clientID = clientId;
          enablePKCEAuthentication = true;
          # groups_name puts plain group names (admins) in the groups claim.
          requestedScopes = [
            "openid"
            "profile"
            "email"
            "groups_name"
          ];
        };

        # policy.default applies to every authenticated user, so policy.csv adds nothing until the default is lowered.
        resources.configMaps.argocd-rbac-cm.data = {
          scopes = "[groups]";
          "policy.default" = "role:admin";
          "policy.csv" = "g, admins, role:admin";
        };

        resources.kanidmOAuth2Clients.${clientId}.spec = {
          kanidmRef = cluster.methods.kanidm.ref;
          displayname = "Argo CD";
          origin = "https://${hostname}";
          redirectUrl = [ "https://${hostname}/auth/callback" ];
          public = true;
          # The CLI listens on http://localhost:8085/auth/callback (--sso-port). Kanidm accepts any
          # loopback redirect on a public client with this set, so it needs no redirectUrl entry.
          allowLocalhostRedirect = true;
          # The scopes are only granted to admins, so nobody else can finish a login.
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
        };
      };
    };
}
