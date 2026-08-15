# External Secrets Operator, reading from OpenBao (modules/kubernetes/openbao/
# default.nix) via ESO's dedicated openBao provider — chosen over reading
# from 1Password directly (see the external-secrets-1password branch/PR #230)
# because 1Password's API rate limits have caused real operational problems
# before. OpenBao is self-hosted, in-cluster, so there's no external API to
# rate-limit against.
#
# Auth is OpenBao's AppRole method, not Kubernetes auth: Kubernetes auth for
# ESO's openBao provider only exists on external-secrets' unreleased main
# branch as of this writing (verified against the actual CRD bundled in the
# pinned chart version, not just upstream docs — the release notes/CRD
# should be re-checked before switching once a release ships it). AppRole's
# role_id is a fixed, non-secret string (tf-modules/openbao-config sets it
# explicitly rather than letting OpenBao generate one, so Nix doesn't need a
# Terraform output round-tripped back in); the secret_id is the one real
# credential ESO holds, delivered as a k8s Secret that
# tf-modules/openbao-config creates directly (via the kubernetes provider,
# using the human's own kubeconfig at apply time) — never through Nix, never
# through node1.
#
# ExternalSecret/ClusterSecretStore aren't core Kubernetes types, so nixidy
# has no built-in typed options for them — generators.fromChartCRDModule (the
# same technique modules/kubernetes/cert-manager/default.nix uses for
# ClusterIssuer/Certificate) generates them live from the chart's own CRDs.
# ExternalSecret is included here (not just ClusterSecretStore) so any other
# app aspect can declare its own `resources.externalSecrets.<name>` — see
# modules/kubernetes/_secrets-lib.nix's mkExternalSecretData.
_: {
  den.aspects.external-secrets.k8s-manifests =
    { charts, generators, ... }:
    {
      nixidy.applicationImports = [
        (generators.fromChartCRDModule {
          name = "external-secrets";
          chart = charts.external-secrets.external-secrets;
          kindFilter = [
            "ClusterSecretStore"
            "ExternalSecret"
          ];
          extraOpts = [
            "--set"
            "installCRDs=true"
          ];
        })
      ];

      applications.external-secrets = {
        namespace = "external-secrets";
        createNamespace = true;

        helm.releases.external-secrets = {
          chart = charts.external-secrets.external-secrets;
          values = {
            installCRDs = true;
          };
        };

        # openbao.kidibox.net -> modules/routerosDevices/rb5009.nix's
        # dns_static_records, pointed at the fixed LoadBalancer IP
        # modules/kubernetes/openbao/default.nix reserves. Plain http: the
        # chart's default listener has tls_disable = 1 (LAN-internal traffic
        # only, same trust model as this repo's other internal Terraform
        # providers e.g. the RouterOS one hitting 10.99.0.1 directly).
        resources.clusterSecretStores.openbao.spec.provider.openBao = {
          server = "http://openbao.kidibox.net:8200";
          path = "secret";
          version = "v2";
          auth.appRole = {
            path = "approle";
            roleId = "external-secrets";
            secretRef = {
              name = "openbao-approle";
              key = "secret_id";
              namespace = "external-secrets";
            };
          };
        };
      };
    };
}
