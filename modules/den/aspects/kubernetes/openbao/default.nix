_: {
  den.aspects.kubernetes.openbao.k8s-manifests =
    { charts, ... }:
    {
      applications.openbao = {
        namespace = "openbao";
        createNamespace = true;

        helm.releases.openbao = {
          chart = charts.openbao.openbao;
          values.server = {
            ha = {
              enabled = true;
              replicas = 1;
              raft.enabled = true;
            };
            dataStorage.storageClass = "miroir";
          };
        };

        resources.externalSecrets.openbao-unseal.spec = {
          secretStoreRef = {
            name = "onepassword";
            kind = "ClusterSecretStore";
          };
          target.name = "openbao-unseal";
          data = [
            {
              secretKey = "unsealKey";
              # <item>/[section/]<field> — the only key format this provider
              # reads for `data[]` entries; a separate `property` is silently
              # ignored (that's only for `dataFrom[].extract`).
              remoteRef.key = "openbao-unseal-key/unseal-key";
            }
          ];
        };

        resources.cronJobs.openbao-unseal.spec = {
          schedule = "* * * * *";
          jobTemplate.spec.template.spec = {
            restartPolicy = "OnFailure";
            containers = [
              {
                name = "unseal";
                image = "openbao/openbao:2.6.2";
                command = [
                  "sh"
                  "-c"
                  "bao operator unseal \"$(cat /unseal/unsealKey)\""
                ];
                env = [
                  {
                    name = "BAO_ADDR";
                    value = "http://openbao.openbao.svc:8200";
                  }
                ];
                volumeMounts = [
                  {
                    name = "unseal";
                    mountPath = "/unseal";
                    readOnly = true;
                  }
                ];
              }
            ];
            volumes = [
              {
                name = "unseal";
                secret.secretName = "openbao-unseal";
              }
            ];
          };
        };

        resources.snapshotPolicies.openbao-data.spec = {
          repository.name = "r2";
          sources = [ { pvc.name = "data-openbao-0"; } ];
          identity = {
            username = "openbao";
            hostname = "openbao";
          };
          retention = {
            keepDaily = 14;
            keepWeekly = 4;
          };
        };

        resources.snapshotSchedules.openbao-data.spec = {
          policyRef.name = "openbao-data";
          schedule = {
            cron = "H * * * *";
            jitter = "5m";
            runOnCreate = false;
          };
        };

        resources.restores.openbao-data.spec = {
          source.fromPolicy = {
            name = "openbao-data";
            offset = 0;
          };
          target.populator = { };
          policy.onMissingSnapshot = "Continue";
        };

        resources.persistentVolumeClaims.data-openbao-0.spec = {
          storageClassName = "miroir";
          accessModes = [ "ReadWriteOnce" ];
          resources.requests.storage = "10Gi";
          dataSourceRef = {
            apiGroup = "kopiur.home-operations.com";
            kind = "Restore";
            name = "openbao-data";
          };
        };
      };
    };
}
