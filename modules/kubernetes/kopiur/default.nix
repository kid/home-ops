{ lib, ... }:
let
  # Builds the four kopiur objects a PVC-backed app needs: the PVC itself
  # (restored from the named Restore), the SnapshotPolicy, its hourly
  # SnapshotSchedule, and the Restore. uid must match the app's own pod
  # uid/gid — the kopiur mover only reads files it owns or that are
  # world-readable (https://kopiur.home-operations.com/permissions/).
  # existingClaim backs up a PVC something else creates (e.g. a StatefulSet
  # volumeClaimTemplate) instead: no PVC here, and that claim must carry the
  # dataSourceRef to Restore `name` itself. ignore lists paths the app can
  # rebuild (caches, logs), kept out of the snapshots. The claim and staging
  # classes are the cluster's den.clusters.<name>.storage ones.
  mkKopiurBackup =
    cluster:
    {
      name,
      uid ? 1000,
      storage ? "1Gi",
      existingClaim ? null,
      ignore ? [ ],
    }:
    lib.optionalAttrs (existingClaim == null) {
      persistentVolumeClaims.${name}.spec = {
        storageClassName = cluster.storage.replicatedClass;
        accessModes = [ "ReadWriteOncePod" ];
        resources.requests.storage = storage;
        dataSourceRef = {
          apiGroup = "kopiur.home-operations.com";
          kind = "Restore";
          inherit name;
        };
      };
    }
    // {
      snapshotPolicies.${name}.spec = {
        repository = {
          kind = "ClusterRepository";
          name = "r2";
        };
        credentialProjection.enabled = true;
        # The staged copy is read once and dropped: on prd, one copy-on-write
        # leg of the snapshot, without a DRBD layer.
        staging.storageClassName = cluster.storage.localClass;
        mover = {
          securityContext = {
            runAsUser = uid;
            runAsGroup = uid;
          };
          resources.requests = {
            cpu = "50m";
            memory = "192Mi";
          };
        };
        sources = [ { pvc.name = if existingClaim == null then name else existingClaim; } ];
        identity = {
          username = name;
          hostname = name;
        };
        retention = {
          keepDaily = 14;
          keepWeekly = 4;
        };
      }
      // lib.optionalAttrs (ignore != [ ]) {
        # Replaces kopiur's default rules wholesale; /lost+found is the only
        # one an ext4 volume has.
        files.ignoreRules = [ "/lost+found" ] ++ ignore;
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
  den.clusterMethods.mkKopiurBackup = mkKopiurBackup;

  # The on-premises mirror of the r2 repository (the RepositoryReplication
  # below). Daily ZFS snapshots on node0 keep a bad sync, which `--delete`
  # would otherwise propagate, from overwriting every copy.
  den.aspects.kubernetes.kopiur.nfs-exports = { cluster, ... }: [
    (
      cluster.methods.nfsExport "kopiur"
      // {
        # kopia already compresses and encrypts its blobs.
        properties = {
          recordsize = "1M";
          compression = "off";
        };
        sanoid = {
          autosnap = true;
          autoprune = true;
          hourly = 0;
          daily = 14;
          monthly = 0;
          yearly = 0;
        };
      }
    )
  ];

  den.aspects.kubernetes.kopiur.k8s-manifests =
    {
      charts,
      generators,
      cluster,
      ...
    }:
    let
      r2Endpoint = "${cluster.cloudflare.accountId}.r2.cloudflarestorage.com";
      # The node0 export holding the mirror. Exported with root_squash and owned
      # nobody:nogroup, and kopia writes its files 0600: every mover touching
      # it runs as 65534.
      mirrorBackend.filesystem = {
        path = "/repo";
        volume.nfs = {
          server = cluster.methods.mediaNfsServer;
          inherit (cluster.methods.nfsExport "kopiur") path;
        };
      };
      nobody = {
        runAsUser = 65534;
        runAsGroup = 65534;
      };
    in
    {
      nixidy.applicationImports = [
        (generators.fromChartCRDModule {
          name = "kopiur";
          chart = charts.home-operations.kopiur;
          kindFilter = [
            "ClusterRepository"
            "RepositoryReplication"
            "SnapshotSchedule"
            "Restore"
            "SnapshotPolicy"
          ];
        })
      ];

      applications.kopiur = {
        namespace = "kopiur-system";

        resources.ciliumNetworkPolicies =
          with cluster.methods.netpol;
          let
            app = component: {
              "app.kubernetes.io/name" = "kopiur";
              "app.kubernetes.io/component" = component;
            };
            r2Egress = fqdnEgress [ r2Endpoint ] [ 443 ];
          in
          {
            kopiur-controller = mkPolicy (app "controller") {
              ingress = [ (scrapeIngress [ 8081 ]) ];
              egress = [
                apiserverEgress
                r2Egress
              ];
            };
            kopiur-webhook = mkPolicy (app "webhook") {
              ingress = [
                (webhookIngress 8443)
                (scrapeIngress [ 8443 ])
              ];
              egress = [ apiserverEgress ];
            };
          };

        resources.ciliumClusterwideNetworkPolicies.kopiur-mover =
          with cluster.methods.netpol;
          mkPolicy { "app.kubernetes.io/managed-by" = "kopiur"; } {
            egress = [
              apiserverEgress
              (fqdnEgress [ r2Endpoint ] [ 443 ])
            ];
          };

        helm.releases.kopiur = {
          chart = charts.home-operations.kopiur;
          values = {
            features.credentialProjection.enabled = true;
            # One replica, no leader election (lease renewals were most of
            # etcd's writes); Recreate below keeps an update from running two.
            leaderElection.enabled = false;

            monitoring = {
              serviceMonitor.enabled = true;
              dashboards = {
                enabled = true;
                grafanaOperator = {
                  enabled = true;
                  matchLabels.dashboards = "grafana";
                };
              };
            };

            resources = {
              requests = {
                cpu = "10m";
                memory = "128Mi";
              };
              limits.memory = "256Mi";
            };

            webhook = {
              serviceMonitor.enabled = true;
              resources = {
                requests = {
                  cpu = "10m";
                  memory = "64Mi";
                };
                limits.memory = "128Mi";
              };
            };
          };
        };

        resources.deployments.kopiur-controller.spec.strategy.type = "Recreate";
      };

      # Separate from the controller: its webhook must serve before the repository is applied.
      applications.kopiur-config = {
        namespace = "kopiur-system";
        flux.dependsOn = [
          "kopiur"
          "external-secrets-config"
        ];

        resources.externalSecrets.kopiur-r2 = {
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
            endpoint = r2Endpoint;
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

        # A blob-level copy of r2 (`kopia repository sync-to`): same format and
        # password, so `local` below opens it. Its credentials are r2's own
        # Secret, which must sit in this namespace (no credential projection
        # here).
        resources.repositoryReplications.r2-local.spec = {
          sourceRef = {
            kind = "ClusterRepository";
            name = "r2";
          };
          destination = mirrorBackend;
          schedule.cron = "30 * * * *";
          # Track r2's retention and maintenance instead of growing forever.
          sync.deleteExtra = true;
          mover = {
            securityContext = nobody;
            resources.requests = {
              cpu = "50m";
              memory = "192Mi";
            };
          };
        };

        # Restore-only: no SnapshotPolicy may point here (ReadOnly refuses
        # backups and runs no maintenance; r2's carries over in the sync). Its
        # movers run as 65534; a Restore setting another uid can't read it.
        resources.clusterRepositories.local.spec = {
          mode = "ReadOnly";
          allowedNamespaces.all = true;
          backend = mirrorBackend;
          encryption.passwordSecretRef = {
            name = "kopiur-r2";
            key = "KOPIA_PASSWORD";
            namespace = "kopiur-system";
          };
          credentialProjection.allowed = true;
          # Filled by the replication only.
          create.enabled = false;
          # Restores name a kopia identity; no duplicate Snapshot catalog of r2's.
          catalog.retain.perIdentity = 0;
          moverDefaults.securityContext = nobody;
        };
      };
    };
}
