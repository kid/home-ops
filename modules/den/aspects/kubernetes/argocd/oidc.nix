# Log in through Kanidm. Separate from default.nix so that file doesn't depend on Kanidm.
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

        # No local login. If Kanidm is down, fix it through git and kubectl on the node.
        resources.configMaps.argocd-cm.data."admin.enabled" = "false";

        # One public client for the UI and the CLI: Kanidm gives each client its own issuer,
        # so a separate cliClientID would fail the issuer check.
        resources.configMaps.argocd-cm.data."oidc.config" = builtins.toJSON {
          name = "Kanidm";
          issuer = cluster.methods.kanidm.issuer clientId;
          clientID = clientId;
          enablePKCEAuthentication = true;
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
          allowLocalhostRedirect = true;
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
