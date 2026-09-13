_: {
  den.aspects.kubernetes.openbao.k8s-manifests =
    { charts, ... }:
    {
      applications.openbao = {
        namespace = "openbao";
        createNamespace = true;
        annotations."argocd.argoproj.io/sync-wave" = "-1";

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
              remoteRef = {
                key = "OpenBao - unseal key";
                property = "unsealKey";
              };
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

        resources.serviceAccounts.openbao-init = { };

        resources.roles.openbao-init.rules = [
          {
            apiGroups = [ "" ];
            resources = [ "secrets" ];
            verbs = [
              "get"
              "create"
              "update"
            ];
          }
        ];

        resources.roleBindings.openbao-init = {
          roleRef = {
            apiGroup = "rbac.authorization.k8s.io";
            kind = "Role";
            name = "openbao-init";
          };
          subjects = [
            {
              kind = "ServiceAccount";
              name = "openbao-init";
              namespace = "openbao";
            }
          ];
        };

        resources.jobs.openbao-init.spec = {
          backoffLimit = 3;
          template.spec = {
            serviceAccountName = "openbao-init";
            restartPolicy = "OnFailure";
            initContainers = [
              {
                name = "init";
                image = "openbao/openbao:2.6.2";
                env = [
                  {
                    name = "BAO_ADDR";
                    value = "http://openbao.openbao.svc:8200";
                  }
                ];
                command = [
                  "sh"
                  "-c"
                  ''
                    set -e

                    while true; do
                      bao status >/dev/null 2>&1
                      code=$?
                      [ "$code" -ne 1 ] && break
                      echo "Waiting for OpenBao API..."
                      sleep 5
                    done

                    if bao status -format=json | grep -q '"initialized": *true'; then
                      echo "Already initialized, nothing to do."
                      exit 0
                    fi

                    init=$(bao operator init -key-shares=1 -key-threshold=1 -format=json)
                    unseal_key=$(printf '%s' "$init" | grep -o '"unseal_keys_b64": *\[ *"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/')
                    root_token=$(printf '%s' "$init" | grep -o '"root_token": *"[^"]*"' | sed 's/.*: *"\([^"]*\)"/\1/')

                    bao operator unseal "$unseal_key"

                    export BAO_TOKEN="$root_token"
                    bao secrets enable -path=secret kv-v2 || true
                    bao auth enable kubernetes || true
                    bao write auth/kubernetes/config kubernetes_host="https://kubernetes.default.svc"
                    printf 'path "secret/data/*" {\n  capabilities = ["read"]\n}\n' | bao policy write eso-cluster -
                    bao write auth/kubernetes/role/eso-cluster \
                      bound_service_account_names=external-secrets \
                      bound_service_account_namespaces=external-secrets \
                      policies=eso-cluster \
                      ttl=1h

                    printf '%s' "$unseal_key" > /shared/unsealKey
                  ''
                ];
                volumeMounts = [
                  {
                    name = "shared";
                    mountPath = "/shared";
                  }
                ];
              }
            ];
            containers = [
              {
                name = "push";
                image = "bitnami/kubectl:1.31";
                command = [
                  "sh"
                  "-c"
                  ''
                    set -e
                    if [ ! -f /shared/unsealKey ]; then
                      echo "Nothing to push (already initialized)."
                      exit 0
                    fi
                    kubectl create secret generic openbao-init-output -n openbao \
                      --from-file=unsealKey=/shared/unsealKey \
                      --dry-run=client -o yaml | kubectl apply -f -
                  ''
                ];
                volumeMounts = [
                  {
                    name = "shared";
                    mountPath = "/shared";
                    readOnly = true;
                  }
                ];
              }
            ];
            volumes = [
              {
                name = "shared";
                emptyDir = { };
              }
            ];
          };
        };

        resources.pushSecrets.openbao-init-output.spec = {
          secretStoreRefs = [
            {
              name = "onepassword";
              kind = "ClusterSecretStore";
            }
          ];
          selector.secret.name = "openbao-init-output";
          data = [
            {
              match = {
                secretKey = "unsealKey";
                remoteRef = {
                  remoteKey = "OpenBao - unseal key";
                  property = "unsealKey";
                };
              };
            }
          ];
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
