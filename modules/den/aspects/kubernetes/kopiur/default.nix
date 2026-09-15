_: {
  den.aspects.kubernetes.kopiur.k8s-manifests =
    { charts, generators, ... }:
    {
      nixidy.applicationImports = [
        (generators.fromChartCRDModule {
          name = "kopiur";
          chart = charts.home-operations.kopiur;
          kindFilter = [
            "Repository"
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
            data = [
              {
                secretKey = "AWS_ACCESS_KEY_ID";
                remoteRef = {
                  key = "kopiur - R2 credentials";
                  property = "accessKeyId";
                };
              }
              {
                secretKey = "AWS_SECRET_ACCESS_KEY";
                remoteRef = {
                  key = "kopiur - R2 credentials";
                  property = "secretAccessKey";
                };
              }
              {
                secretKey = "KOPIA_PASSWORD";
                remoteRef = {
                  key = "kopiur - R2 credentials";
                  property = "repositoryPassword";
                };
              }
            ];
          };
        };

        resources.repositories.r2.spec = {
          backend.s3 = {
            bucket = "home-ops-kopiur";
            auth.secretRef.name = "kopiur-r2";
          };
          encryption.passwordSecretRef = {
            name = "kopiur-r2";
            key = "KOPIA_PASSWORD";
          };
          create.enabled = true;
        };
      };
    };
}
