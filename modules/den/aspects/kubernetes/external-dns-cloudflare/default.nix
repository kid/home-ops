# Second external-dns instance: Cloudflare's own zone, for apps opted into
# the public internet via cloudflared/default.nix's tunnel Gateway. Separate
# from external-dns/default.nix (Mikrotik provider, internal split-horizon
# DNS) — different backend, different credential, different policy.
_: {
  den.aspects.kubernetes.external-dns-cloudflare.k8s-manifests =
    { charts, cluster, ... }:
    {
      applications.external-dns-cloudflare = {
        namespace = "external-dns-cloudflare";

        helm.releases.external-dns-cloudflare = {
          chart = charts.kubernetes-sigs.external-dns;
          values = {
            fullnameOverride = "external-dns-cloudflare";
            replicaCount = 1;
            sources = [ "gateway-httproute" ];
            serviceMonitor.enabled = true;

            registry = "txt";
            txtOwnerId = cluster.name;
            domainFilters = [ cluster.domain ];
            # Not "sync" like the Mikrotik instance: this writes to the real
            # public zone, so removing an app's opt-in label must not
            # auto-delete its public record — cleanup is a manual step.
            policy = "upsert-only";

            provider.name = "cloudflare";

            env = [
              {
                name = "CF_API_TOKEN";
                valueFrom.secretKeyRef = {
                  name = "cloudflare-external-dns-token";
                  key = "token";
                };
              }
            ];

            extraArgs = [
              # Cloudflare Tunnel only routes proxied ("orange-cloud") records.
              "--cloudflare-proxied"
              # The real per-app opt-in gate: only HTTPRoutes carrying this
              # label get a public DNS record. Without it this instance would
              # otherwise pick up every gateway-httproute in the cluster,
              # including ones bound to the internal "apps" Gateway.
              "--label-filter=home-ops.dev/public-dns=true"
            ];
          };
        };

        resources.externalSecrets.cloudflare-external-dns-token.spec = {
          secretStoreRef = {
            name = "onepassword";
            kind = "ClusterSecretStore";
          };
          target.name = "cloudflare-external-dns-token";
          data = [
            {
              secretKey = "token";
              remoteRef.key = "cloudflare-external-dns-token/credentials/token";
            }
          ];
        };
      };
    };
}
