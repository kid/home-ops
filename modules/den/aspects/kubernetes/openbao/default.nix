_: {
  den.aspects.kubernetes.openbao.k8s-manifests =
    { charts, cluster, ... }:
    {
      applications.openbao = {
        namespace = "openbao";
        createNamespace = true;
        annotations."argocd.argoproj.io/sync-wave" = "-1";

        # OpenBao's kubernetes auth method calls the TokenReview API to
        # validate a login's ServiceAccount token — needs auth-delegator.
        resources.clusterRoleBindings.openbao-auth-delegator = {
          roleRef = {
            apiGroup = "rbac.authorization.k8s.io";
            kind = "ClusterRole";
            name = "system:auth-delegator";
          };
          subjects = [
            {
              kind = "ServiceAccount";
              name = "openbao";
              namespace = "openbao";
            }
          ];
        };

        # The chart applies `server.service.type` to its active and standby
        # Services too, and its annotations to all of them, so the one
        # external endpoint is a Service of its own.
        resources.services.openbao-external = {
          metadata.annotations."external-dns.alpha.kubernetes.io/hostname" = "openbao.${cluster.domain}";
          spec = {
            type = "LoadBalancer";
            selector = {
              "app.kubernetes.io/name" = "openbao";
              component = "server";
            };
            ports = [
              {
                name = "http";
                port = 8200;
                targetPort = 8200;
              }
            ];
          };
        };

        helm.releases.openbao = {
          chart = charts.openbao.openbao;
          values.server = {
            ha = {
              enabled = true;
              replicas = 1;
              raft = {
                enabled = true;
                config = ''
                  ui = true

                  listener "tcp" {
                    tls_disable = 1
                    address = "[::]:8200"
                    cluster_address = "[::]:8201"
                  }

                  storage "raft" {
                    path = "/openbao/data"
                  }

                  service_registration "kubernetes" {}

                  seal "static" {
                    current_key_id = "1"
                    current_key    = "file:///vault/unseal/unsealKey"
                  }

                  initialize "kv" {
                    request "mount-kv" {
                      operation = "update"
                      path      = "sys/mounts/secret"
                      data = {
                        type    = "kv"
                        options = { version = "2" }
                      }
                    }
                  }

                  initialize "kubernetes-auth" {
                    request "enable" {
                      operation = "update"
                      path      = "sys/auth/kubernetes"
                      data      = { type = "kubernetes" }
                    }

                    request "configure" {
                      operation = "update"
                      path      = "auth/kubernetes/config"
                      data = {
                        kubernetes_host = "https://kubernetes.default.svc"
                      }
                    }

                    request "policy" {
                      operation = "update"
                      path      = "sys/policies/acl/eso-cluster"
                      data = {
                        # secret/data/* covers everything ESO reads; the
                        # approle paths let the one-time bootstrap step
                        # (kubectl exec into an external-secrets pod, no
                        # persisted root token) hand cluster-secrets its
                        # own role_id/secret_id.
                        policy = <<-EOT
                          path "secret/data/*" {
                            capabilities = ["read"]
                          }
                          path "auth/approle/role/cluster-secrets/role-id" {
                            capabilities = ["read"]
                          }
                          path "auth/approle/role/cluster-secrets/secret-id" {
                            capabilities = ["create", "update"]
                          }
                        EOT
                      }
                    }

                    request "role" {
                      operation = "update"
                      path      = "auth/kubernetes/role/eso-cluster"
                      data = {
                        bound_service_account_names      = ["external-secrets"]
                        bound_service_account_namespaces = ["external-secrets"]
                        policies                          = ["eso-cluster"]
                      }
                    }
                  }

                  initialize "approle-auth" {
                    request "enable" {
                      operation = "update"
                      path      = "sys/auth/approle"
                      data      = { type = "approle" }
                    }

                    request "policy" {
                      operation = "update"
                      path      = "sys/policies/acl/cluster-secrets"
                      data = {
                        policy = <<-EOT
                          path "secret/data/*" {
                            capabilities = ["create", "update"]
                          }
                        EOT
                      }
                    }

                    request "role" {
                      operation = "update"
                      path      = "auth/approle/role/cluster-secrets"
                      data      = { token_policies = ["cluster-secrets"] }
                    }
                  }
                '';
              };
            };
            dataStorage.storageClass = "miroir";
            volumes = [
              {
                name = "unseal";
                secret.secretName = "openbao-unseal";
              }
            ];
            volumeMounts = [
              {
                name = "unseal";
                mountPath = "/vault/unseal";
                readOnly = true;
              }
            ];
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

        resources.snapshotPolicies.openbao-data.spec = {
          repository = {
            kind = "ClusterRepository";
            name = "r2";
          };
          credentialProjection.enabled = true;
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
          credentialProjection.enabled = true;
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
