# GitHub push webhook for Flux's root GitRepository: a notification-controller
# Receiver behind the public Cloudflare Tunnel Gateway, and the GitHub webhook
# plus its 1Password-held HMAC token, this aspect's tofu resources. The Receiver serves
# /hook/sha256(token + name + namespace), so tofu computes the URL from the
# token it generates; nothing flows back from the cluster.
_:
let
  receiverName = "github";
  namespace = "flux-system";
  tokenSecret = "github-webhook-token";
  # Its tofu onepassword_item's title.
  tokenItem = "flux-github-webhook";
  hostname = cluster: cluster.methods.mkAppHostname "flux-webhook";
in
{
  den.aspects.kubernetes.flux-webhook = {
    k8s-manifests =
      {
        cluster,
        generators,
        pkgs,
        ...
      }:
      {
        nixidy.applicationImports = [
          (generators.fromCRDModule {
            name = "flux-notification";
            src = pkgs.fetchFromGitHub {
              owner = "fluxcd";
              repo = "notification-controller";
              # renovate: datasource=github-releases depName=fluxcd/notification-controller
              rev = "v1.10.1";
              hash = "sha256-ctrOmEpStwfOkOb9uMaKvBZawTaT9GMsRZEKUYuJ0OI=";
            };
            crdFiles = [ "config/crd/bases/notification.toolkit.fluxcd.io_receivers.yaml" ];
            kindFilter = [ "Receiver" ];
          })
        ];

        # Separate from flux-operator: the Receiver CRD only exists once the
        # FluxInstance (Ready gates flux-operator) has installed notification-controller.
        applications.flux-webhook = {
          inherit namespace;
          flux.dependsOn = [
            "flux-operator"
            "external-secrets-config"
          ];

          resources.externalSecrets.${tokenSecret}.spec = {
            secretStoreRef = {
              name = "onepassword";
              kind = "ClusterSecretStore";
            };
            target.name = tokenSecret;
            data = [
              {
                secretKey = "token";
                remoteRef.key = "${tokenItem}/credentials/token";
              }
            ];
          };

          resources.receivers.${receiverName}.spec = {
            type = "github";
            events = [
              "ping"
              "push"
            ];
            secretRef.name = tokenSecret;
            resources = [
              {
                apiVersion = "source.toolkit.fluxcd.io/v1";
                kind = "GitRepository";
                name = "flux-system";
              }
            ];
          };

          resources.httpRoutes.flux-webhook = {
            metadata.labels."home-ops.dev/public-dns" = "true";
            spec = {
              parentRefs = [
                {
                  group = "gateway.networking.k8s.io";
                  kind = "Gateway";
                  name = "cloudflare-tunnel";
                  namespace = "cloudflare-tunnel-system";
                  sectionName = "http";
                }
              ];
              hostnames = [ (hostname cluster) ];
              rules = [
                {
                  # Only the receiver paths are public.
                  matches = [
                    {
                      path = {
                        type = "PathPrefix";
                        value = "/hook/";
                      };
                    }
                  ];
                  backendRefs = [
                    {
                      group = "";
                      kind = "Service";
                      name = "webhook-receiver";
                      port = 80;
                      weight = 1;
                    }
                  ];
                }
              ];
            };
          };
        };
      };

    tofu =
      { cluster, ... }:
      let
        match = builtins.match "https://github\\.com/([^/]+)/([^.]+)\\.git" cluster.nixidy.repository;
      in
      {
        data.onepassword_vault.home_ops_prd.name = cluster.secrets.onepasswordVault;

        # No token set: falls back to `gh auth token` on the machine running apply.
        provider.github.default.owner = builtins.elemAt match 0;

        resource.random_password.flux_webhook_token = {
          length = 40;
          special = false;
        };

        resource.onepassword_item.flux_webhook_token = {
          vault = "\${data.onepassword_vault.home_ops_prd.uuid}";
          title = tokenItem;
          category = "secure_note";
          section = [
            {
              label = "credentials";
              field = [
                {
                  label = "token";
                  type = "CONCEALED";
                  value = "\${random_password.flux_webhook_token.result}";
                }
              ];
            }
          ];
        };

        resource.github_repository_webhook.flux = {
          repository = builtins.elemAt match 1;
          configuration = {
            url = ''https://${hostname cluster}/hook/''${sha256("''${random_password.flux_webhook_token.result}${receiverName}${namespace}")}'';
            content_type = "json";
            secret = "\${random_password.flux_webhook_token.result}";
            insecure_ssl = false;
          };
          active = true;
          events = [ "push" ];
        };
      };
  };
}
