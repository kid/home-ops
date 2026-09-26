_:
let
  # Builds the four kopiur objects a PVC-backed app needs: the PVC itself
  # (restored from the named Restore), the SnapshotPolicy, its hourly
  # SnapshotSchedule, and the Restore. uid must match the app's own pod
  # uid/gid — the kopiur mover only reads files it owns or that are
  # world-readable (https://kopiur.home-operations.com/permissions/).
  mkKopiurBackup =
    {
      name,
      uid ? 1000,
      storage ? "1Gi",
    }:
    {
      persistentVolumeClaims.${name}.spec = {
        storageClassName = "miroir";
        accessModes = [ "ReadWriteOnce" ];
        resources.requests.storage = storage;
        dataSourceRef = {
          apiGroup = "kopiur.home-operations.com";
          kind = "Restore";
          inherit name;
        };
      };
      snapshotPolicies.${name}.spec = {
        repository = {
          kind = "ClusterRepository";
          name = "r2";
        };
        credentialProjection.enabled = true;
        mover.securityContext = {
          runAsUser = uid;
          runAsGroup = uid;
        };
        sources = [ { pvc.name = name; } ];
        identity = {
          username = name;
          hostname = name;
        };
        retention = {
          keepDaily = 14;
          keepWeekly = 4;
        };
      };
      snapshotSchedules.${name}.spec = {
        policyRef.name = name;
        schedule = {
          cron = "H * * * *";
          jitter = "5m";
          runOnCreate = false;
        };
      };
      restores.${name}.spec = {
        source.fromPolicy = {
          inherit name;
          offset = 0;
        };
        target.populator = { };
        policy.onMissingSnapshot = "Continue";
        credentialProjection.enabled = true;
      };
    };
in
{
  # Every cluster that includes this aspect needs the method — den has no
  # reverse "which clusters include me" lookup, and reading config.den.clusters
  # here to generalize it would self-reference (infinite recursion), so list
  # clusters explicitly.
  den.clusters.prd.methods.mkKopiurBackup = mkKopiurBackup;

  den.aspects.kubernetes.kopiur.k8s-manifests =
    {
      charts,
      generators,
      cluster,
      ...
    }:
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
        annotations."argocd.argoproj.io/sync-wave" = "-2";

        helm.releases.kopiur = {
          chart = charts.home-operations.kopiur;
          values.features.credentialProjection.enabled = true;
        };

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

        resources.clusterRepositories.r2.spec = {
          allowedNamespaces.all = true;
          backend.s3 = {
            bucket = "home-ops-${cluster.environment}-kopiur";
            endpoint = "${cluster.cloudflare.accountId}.r2.cloudflarestorage.com";
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
          credentialProjection.allowed = true;
          create.enabled = true;
        };
      };
    };
}
