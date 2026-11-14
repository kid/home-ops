{ den, lib, ... }:
let
  # Root with kopiur's privilegedMode: DAC_OVERRIDE to read every file of a
  # backup whatever its owner, CHOWN/FOWNER/FSETID to give each restored file
  # its recorded owner back. Movers in a namespace whose app declares one get
  # the namespace's privileged-movers opt-in (the k8s-manifests below). On
  # node0's root_squash export, a root mover's NFS requests still land as
  # 65534, the owner of every file of the local repository.
  rootMover = {
    securityContext = {
      runAsUser = 0;
      runAsGroup = 0;
      runAsNonRoot = false;
    };
    privilegedMode = true;
  };

  # Builds the kopiur objects a PVC-backed app needs: the PVC itself
  # (restored from the named Restore), the SnapshotPolicy, its hourly
  # SnapshotSchedule, and the Restore. uid must match the app's own pod
  # uid/gid — the kopiur mover only reads files it owns or that are
  # world-readable (https://kopiur.home-operations.com/permissions/).
  # existingClaim backs up a PVC something else creates (e.g. a StatefulSet
  # volumeClaimTemplate) instead: no PVC here, and that claim must carry the
  # dataSourceRef to Restore `name` itself. ignore lists paths the app can
  # rebuild (caches, logs), kept out of the r2 snapshots. The claim and
  # staging classes are the cluster's den.clusters.<name>.storage ones. A
  # cluster without kopiur.backups gets no r2 SnapshotSchedule: the policy
  # only names the identity its Restore reads.
  #
  # With kopiur.local, a second policy `<name>-full` backs the same claim up
  # daily to the on-site `local` repository: no ignore rules, as root, so it
  # also holds what r2 skips. kopiur.restoreFrom = "local" restores from that
  # identity instead of r2's. r2 = false keeps a claim out of r2 altogether
  # (VMSingle's and VLSingle's): it is only backed up with kopiur.local and
  # only gets a Restore with restoreFrom = "local", so its claim may carry the
  # dataSourceRef only then.
  mkKopiurBackup =
    cluster:
    {
      name,
      uid ? 1000,
      storage ? "1Gi",
      existingClaim ? null,
      ignore ? [ ],
      r2 ? true,
    }:
    let
      claim = if existingClaim == null then name else existingClaim;
      full = "${name}-full";
      fromLocal = cluster.kopiur.restoreFrom == "local";
      # The staged copy is read once and dropped: on prd, one copy-on-write
      # leg of the snapshot, without a DRBD layer.
      staging.storageClassName = cluster.storage.localClass;
      moverResources.requests = {
        cpu = "50m";
        memory = "192Mi";
      };
      clusterRepository = repository: {
        kind = "ClusterRepository";
        name = repository;
      };
      restored = r2 || fromLocal;
    in
    lib.optionalAttrs (existingClaim == null) {
      persistentVolumeClaims.${name}.spec = {
        storageClassName = cluster.storage.replicatedClass;
        accessModes = [ "ReadWriteOncePod" ];
        resources.requests.storage = storage;
      }
      // lib.optionalAttrs restored {
        dataSourceRef = {
          apiGroup = "kopiur.home-operations.com";
          kind = "Restore";
          inherit name;
        };
      };
    }
    // {
      snapshotPolicies =
        lib.optionalAttrs r2 {
          ${name}.spec = {
            repository = clusterRepository "r2";
            credentialProjection.enabled = true;
            inherit staging;
            mover = {
              securityContext = {
                runAsUser = uid;
                runAsGroup = uid;
              };
              resources = moverResources;
            };
            sources = [ { pvc.name = claim; } ];
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
        }
        // lib.optionalAttrs cluster.kopiur.local {
          ${full}.spec = {
            repository = clusterRepository "local";
            credentialProjection.enabled = true;
            inherit staging;
            mover = rootMover // {
              resources = moverResources;
            };
            sources = [ { pvc.name = claim; } ];
            identity = {
              username = full;
              hostname = full;
            };
            # node0 keeps 14 daily ZFS snapshots of the repository on top.
            retention = {
              keepDaily = 7;
              keepWeekly = 4;
            };
            files.ignoreRules = [ "/lost+found" ];
          };
        };
      # By hand: `kubectl kopiur snapshot now <policy>`, or `kubectl create` a
      # Snapshot with spec.policyRef.name <policy>.
      snapshotSchedules =
        lib.optionalAttrs (r2 && cluster.kopiur.backups) {
          ${name}.spec = {
            policyRef.name = name;
            schedule = {
              cron = "H * * * *";
              jitter = "5m";
              runOnCreate = false;
            };
          };
        }
        // lib.optionalAttrs cluster.kopiur.local {
          ${full}.spec = {
            policyRef.name = full;
            # Before the repository's daily full maintenance at 03:00.
            schedule = {
              cron = "H 1 * * *";
              jitter = "30m";
              runOnCreate = false;
            };
          };
        };
      restores = lib.optionalAttrs restored {
        ${name}.spec = {
          target.populator = { };
          policy.onMissingSnapshot = "Continue";
          credentialProjection.enabled = true;
        }
        // (
          if fromLocal then
            {
              repository = clusterRepository "local";
              # An identity without its sourcePath matches no snapshot.
              source.identity = {
                username = full;
                hostname = full;
                sourcePath = "/pvc/${claim}";
              };
              mover = rootMover;
            }
          else
            {
              source.fromPolicy = {
                inherit name;
                offset = 0;
              };
            }
        );
      };
    };
in
{
  den.clusterMethods.mkKopiurBackup = mkKopiurBackup;

  # The on-site full backup repository (`local` below), on node0's NVMe pool.
  # Daily ZFS snapshots keep a bad maintenance run or a deleted snapshot
  # recoverable; node0 also replicates them to tank (modules/hosts/node0.nix).
  # Only the cluster with kopiur.local writes it: node0 exports it read-write
  # to that cluster's nodes only, read-only to every other Storage client.
  den.aspects.kubernetes.kopiur.nfs-exports =
    { cluster, ... }:
    lib.optionals cluster.kopiur.local [
      (
        cluster.methods.nfsExport "kopiur-local"
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
          writer = cluster.name;
        }
      )
    ];

  den.aspects.kubernetes.kopiur.k8s-manifests =
    {
      charts,
      generators,
      cluster,
      config,
      ...
    }:
    let
      r2Endpoint = "${cluster.cloudflare.accountId}.r2.cloudflarestorage.com";
      inherit (cluster.kopiur) local;
      restoresLocal = cluster.kopiur.restoreFrom == "local";
      # The cluster writing the environment's local repository: this one with
      # kopiur.local, else the single one that has it (opened ReadOnly, like a
      # restore-only cluster's r2).
      localWriter =
        let
          writers =
            den.clusters
            |> lib.filterAttrs (_: c: c.environment == cluster.environment && c.kopiur.local)
            |> lib.attrValues;
        in
        if local then
          cluster
        else if lib.length writers == 1 then
          lib.head writers
        else
          throw "kopiur: cluster ${cluster.name} restores from local, but environment ${cluster.environment} has ${toString (lib.length writers)} clusters with kopiur.local instead of one";
      # Exported with root_squash and owned nobody:nogroup, and kopia writes
      # its files 0600: the repository's own movers run as 65534, and a root
      # mover's requests reach node0 as 65534 too.
      localBackend.filesystem = {
        path = "/repo";
        volume.nfs = {
          server = cluster.methods.mediaNfsServer;
          inherit (localWriter.methods.nfsExport "kopiur-local") path;
        };
      };
      nobody = {
        runAsUser = 65534;
        runAsGroup = 65534;
      };
      appsName = config.nixidy.appOfApps.name;
      # Namespaces whose app has a SnapshotPolicy or Restore with a root
      # mover (rootMover above): kopiur refuses those until the namespace
      # opts in.
      privilegedNamespaces =
        config.applications
        |> lib.filterAttrs (n: _: n != appsName)
        |> lib.filterAttrs (
          _: app:
          lib.any (o: o.spec.mover.privilegedMode or null == true) (
            lib.attrValues app.resources.snapshotPolicies ++ lib.attrValues app.resources.restores
          )
        )
        |> lib.mapAttrsToList (_: app: app.namespace)
        |> lib.unique;
    in
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

      applications.${appsName}.resources.namespaces = lib.genAttrs privilegedNamespaces (_: {
        metadata.annotations."kopiur.home-operations.com/privileged-movers" = "true";
      });

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
              # GrafanaDashboard objects, which need grafana-operator's CRDs.
              dashboards = {
                enabled = cluster.includesAspect den.aspects.kubernetes.grafana-operator;
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

        # Without kopiur.backups, restore-only: ReadOnly refuses backup Jobs
        # and runs no maintenance, and nothing creates the repository.
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
          create.enabled = cluster.kopiur.backups;
        }
        // (
          if cluster.kopiur.backups then
            {
              # Kopia compacts an epoch only once the next one closes, so the
              # current and previous epochs stay uncompacted. At kopia's 24h
              # default, hourly backups kept ~2000 index blobs, past kopiur's
              # 1000 IndexBlobHealth threshold. ReadOnly repositories can't
              # set parameters.
              parameters.epoch.minDuration = "6h";
            }
          else
            { mode = "ReadOnly"; }
        );

        # The on-site full backup repository: the `<name>-full` policies,
        # daily, nothing ignored, VMSingle and VLSingle included. Written and
        # maintained by its kopiur.local cluster only; any other cluster of
        # the environment that restores from it opens it ReadOnly, over an
        # export node0 serves it read-only anyway. Same password as r2.
        resources.clusterRepositories.local = lib.mkIf (local || restoresLocal) {
          spec = {
            allowedNamespaces.all = true;
            backend = localBackend;
            encryption.passwordSecretRef = {
              name = "kopiur-r2";
              key = "KOPIA_PASSWORD";
              namespace = "kopiur-system";
            };
            credentialProjection.allowed = true;
            create.enabled = local;
            # Bootstrap and maintenance; the -full policies and their Restores
            # run as root instead.
            moverDefaults.securityContext = nobody;
          }
          // (
            if local then
              {
                # As r2's above: few index blobs per daily run, but the same
                # bound on what an uncompacted epoch can hold.
                parameters.epoch.minDuration = "6h";
              }
            else
              { mode = "ReadOnly"; }
          );
        };
      };
    };
}
