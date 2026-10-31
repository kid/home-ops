# GitHub push webhook for Flux's root GitRepository: a notification-controller
# Receiver behind the public Cloudflare Tunnel Gateway, and the GitHub webhook
# plus its 1Password-held HMAC token from the flux-webhook Terragrunt stack
# (tf-catalog/modules/flux-webhook). The Receiver serves
# /hook/sha256(token + name + namespace), so tofu computes the URL from the
# token it generates; nothing flows back from the cluster.
_:
let
  receiverName = "github";
  namespace = "flux-system";
  tokenSecret = "github-webhook-token";
  # Must match tf-catalog/modules/flux-webhook's onepassword_item title.
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
              rev = "v1.10.0";
              hash = "sha256-ARMVKx4nUx84DfLFj8mzovbcCJYLwzggbemXSLDKIEQ=";
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

    "terragrunt-stacks" =
      { cluster, ... }:
      let
        match = builtins.match "https://github\\.com/([^/]+)/([^.]+)\\.git" cluster.nixidy.repository;
      in
      {
        stack = "flux-webhook";
        localModule = "flux-webhook";
        inputs = {
          github_owner = builtins.elemAt match 0;
          github_repo = builtins.elemAt match 1;
          webhook_hostname = hostname cluster;
          receiver_name = receiverName;
          receiver_namespace = namespace;
          token_item = tokenItem;
        };
      };
  };
}
