# Log in through Authelia (kubernetes/authelia/default.nix defines both clients). Separate from
# default.nix because that aspect is shared with dev, which has neither Authelia nor External Secrets.
_: {
  den.aspects.kubernetes.argocd-oidc.k8s-manifests =
    { cluster, ... }:
    {
      applications.argocd = {
        resources.configMaps.argocd-cm.data.url = "https://${cluster.methods.mkAppHostname "argocd"}";

        # No local login, so the form is hidden. If Authelia is down, fix it through git and kubectl on the node.
        resources.configMaps.argocd-cm.data."admin.enabled" = "false";

        # cliClientID is for `argocd login --sso`; ArgoCD accepts its tokens without an allowedAudiences entry.
        resources.configMaps.argocd-cm.data."oidc.config" = builtins.toJSON {
          name = "Authelia";
          issuer = "https://${cluster.methods.mkAppHostname "auth"}";
          clientID = "argocd";
          clientSecret = "$argocd-oidc:clientSecret";
          cliClientID = "argocd-cli";
          requestedScopes = [
            "openid"
            "profile"
            "email"
            "groups"
          ];
        };

        # policy.default applies to every authenticated user, so policy.csv adds nothing until the default is lowered.
        resources.configMaps.argocd-rbac-cm.data = {
          scopes = "[groups]";
          "policy.default" = "role:admin";
          "policy.csv" = "g, admins, role:admin";
        };

        # ArgoCD only reads $secret:key values from a Secret with this part-of label.
        resources.externalSecrets.argocd-oidc = {
          metadata.annotations."argocd.argoproj.io/sync-wave" = "-1";
          spec = {
            secretStoreRef = {
              name = "onepassword";
              kind = "ClusterSecretStore";
            };
            target = {
              name = "argocd-oidc";
              template.metadata.labels."app.kubernetes.io/part-of" = "argocd";
            };
            data = [
              {
                secretKey = "clientSecret";
                remoteRef.key = "authelia/secrets/argocd-client-secret";
              }
            ];
          };
        };
      };
    };
}
