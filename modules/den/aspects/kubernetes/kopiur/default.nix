_: {
  den.aspects.kubernetes.kopiur.k8s-manifests =
    { charts, generators, ... }:
    {
      nixidy.applicationImports = [
        (generators.fromChartCRDModule {
          name = "kopiur";
          chart = charts.home-operations.kopiur;
          kindFilter = [
            "ClusterRepository"
            "SnapshotSchedule"
            "Restore"
            "SnapshotPolicy"
          ];
        })
      ];

      applications.kopiur = {
        namespace = "kopiur-system";
        createNamespace = true;

        helm.releases.kopiur.chart = charts.home-operations.kopiur;

        resources.externalSecrets.kopiur-r2 = {
          metadata.annotations."argocd.argoproj.io/sync-wave" = "-1";
          spec = {
            secretStoreRef = {
              name = "onepassword";
              kind = "ClusterSecretStore";
            };
            target.name = "kopiur-r2";
            # <item>/[section/]<field> — the only key format this provider
            # reads for `data[]` entries; a separate `property` is silently
            # ignored (that's only for `dataFrom[].extract`).
            data = [
              {
                secretKey = "AWS_ACCESS_KEY_ID";
                remoteRef.key = "kopiur-r2-credentials/credentials/access-key-id";
              }
              {
                secretKey = "AWS_SECRET_ACCESS_KEY";
                remoteRef.key = "kopiur-r2-credentials/credentials/secret-access-key";
              }
              {
                secretKey = "KOPIA_PASSWORD";
                remoteRef.key = "kopiur-r2-credentials/credentials/repository-password";
              }
            ];
          };
        };

        # ClusterRepository, not Repository — openbao's Restore/SnapshotPolicy
        # live in a different namespace and need to reference this same
        # repository (Repository is namespace-scoped, so they couldn't).
        resources.clusterRepositories.r2.spec = {
          allowedNamespaces.all = true;
          backend.s3 = {
            bucket = "home-ops-kopiur";
            endpoint = "fadfc390b1e5fb0ce019b9f7a8917d42.r2.cloudflarestorage.com";
            region = "auto";
            auth.secretRef = {
              name = "kopiur-r2";
              namespace = "kopiur-system";
            };
          };
          encryption.passwordSecretRef = {
            name = "kopiur-r2";
            key = "KOPIA_PASSWORD";
            namespace = "kopiur-system";
          };
          # Lets kopiur copy the credential Secret into any namespace whose
          # own Snapshot/Restore/Maintenance references this repository.
          credentialProjection.allowed = true;
          create.enabled = true;
        };
      };
    };
}
