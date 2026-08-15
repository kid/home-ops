# External Secrets Operator, reading from 1Password via ESO's SDK provider
# (onepasswordSDK) — a direct 1Password-cloud API integration authenticated
# with a Service Account token, no Connect server deployment needed (fewest
# new moving pieces for a single-node home cluster). "A store is per vault"
# (external-secrets.io/main/provider/1password-sdk) — this repo has exactly
# one 1Password vault (home-ops, matching modules/network/_ros-lib.nix's
# op_vault) and one matching cluster-scoped ClusterSecretStore.
#
# The bootstrap credential this store's auth.serviceAccountSecretRef points
# at (onepassword-service-account-token/token, in the external-secrets
# namespace) is delivered onto node1 outside of ArgoCD entirely — see the
# k3s-external-secrets sops-nix aspect included on node1
# (modules/hosts/node1.nix) — ESO itself has no way to bootstrap the very
# credential it needs to talk to 1Password.
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

        resources.clusterSecretStores.onepassword.spec.provider.onepasswordSDK = {
          vault = "home-ops";
          auth.serviceAccountSecretRef = {
            name = "onepassword-service-account-token";
            key = "token";
            namespace = "external-secrets";
          };
        };
      };
    };
}
