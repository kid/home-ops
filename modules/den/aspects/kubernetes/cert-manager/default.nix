# cert-manager. Installed so Cilium can issue Hubble's mTLS certs through it
# instead of Helm's own genCA/genSignedCert, which re-randomizes on every
# render and made manifests/prd/cilium's certs non-idempotent.
#
# ClusterIssuer/Certificate aren't core Kubernetes types, so nixidy has no
# built-in typed options for them — generators.fromChartCRDModule (a module
# arg nixidy's mkEnv auto-injects) generates them live from the chart's own
# CRDs, no committed file needed, so the self-signed CA + ClusterIssuer
# chain below is real Nix, not embedded YAML. extraOpts is required: the
# chart gates its CRDs behind crds.enabled (default false, same as the
# Helm release's own values below), and kindFilter matches nothing if the
# chart is templated without it.
_: {
  den.aspects.kubernetes.cert-manager.k8s-manifests =
    {
      charts,
      generators,
      cluster,
      ...
    }:
    let
      issuerName = if cluster.letsencrypt.staging then "letsencrypt-staging" else "letsencrypt-prod";
      acmeServer =
        if cluster.letsencrypt.staging then
          "https://acme-staging-v02.api.letsencrypt.org/directory"
        else
          "https://acme-v02.api.letsencrypt.org/directory";
    in
    {
      nixidy.applicationImports = [
        (generators.fromChartCRDModule {
          name = "cert-manager";
          chart = charts.jetstack.cert-manager;
          kindFilter = [
            "Certificate"
            "ClusterIssuer"
          ];
          extraOpts = [
            "--set"
            "crds.enabled=true"
          ];
        })
      ];

      applications.cert-manager = {
        namespace = "cert-manager";

        # Before envoy-gateway, which reads the wildcard cert it pushes to 1Password.
        annotations."argocd.argoproj.io/sync-wave" = "-2";

        helm.releases.cert-manager = {
          chart = charts.jetstack.cert-manager;
          values = {
            crds.enabled = true;
            replicaCount = 1;
          };
        };

        # Standard cert-manager self-signed-root bootstrap: a selfSigned
        # ClusterIssuer signs one CA Certificate, then hubble-ca-issuer
        # (referenced by modules/den/aspects/kubernetes/cilium/default.nix's
        # hubble.tls.auto.certManagerIssuerRef) signs everything else off
        # that CA's secret. Certificate's namespace defaults to this
        # application's own namespace (cert-manager).
        resources.clusterIssuers.selfsigned-issuer.spec.selfSigned = { };

        resources.certificates.hubble-ca.spec = {
          isCA = true;
          commonName = "hubble-ca";
          secretName = "hubble-ca-secret";
          privateKey = {
            algorithm = "ECDSA";
            size = 256;
          };
          issuerRef = {
            name = "selfsigned-issuer";
            kind = "ClusterIssuer";
            group = "cert-manager.io";
          };
        };

        resources.clusterIssuers.hubble-ca-issuer.spec.ca.secretName = "hubble-ca-secret";

        resources.clusterIssuers.${issuerName}.spec.acme = {
          server = acmeServer;
          email = "arnaud.rebts@gmail.com";
          privateKeySecretRef.name = "${issuerName}-account-key";
          solvers = [
            {
              dns01.cloudflare.apiTokenSecretRef = {
                name = "cloudflare-dns-api-token";
                key = "token";
              };
            }
          ];
        };

        # The wildcard cert lives in 1Password so a rebuild imports it instead
        # of asking Let's Encrypt again. Waves (within this app):
        #   -3 seed Secret, -2 seed PushSecret: puts a placeholder in the item
        #      only if it doesn't exist yet, so the import below never fails
        #      on a first-ever deploy.
        #   -1 import: creates wildcard-tls once, carrying the annotations
        #      cert-manager checks before deciding to re-issue. A placeholder
        #      isn't a certificate, so cert-manager issues a real one.
        #    0 Certificate; 1 push the result back to 1Password.
        resources.secrets.wildcard-tls-seed = {
          metadata.annotations."argocd.argoproj.io/sync-wave" = "-3";
          # `data`, not `stringData`: the API server rewrites the latter, which
          # ArgoCD reports as drift. Both values are "placeholder".
          data = {
            "tls.crt" = "cGxhY2Vob2xkZXI=";
            "tls.key" = "cGxhY2Vob2xkZXI=";
          };
        };

        resources.pushSecrets.wildcard-tls-seed = {
          metadata.annotations."argocd.argoproj.io/sync-wave" = "-2";
          spec = {
            updatePolicy = "IfNotExists";
            secretStoreRefs = [
              {
                name = "onepassword";
                kind = "ClusterSecretStore";
              }
            ];
            selector.secret.name = "wildcard-tls-seed";
            template.data = {
              "tls.crt" = ''{{ index . "tls.crt" | b64enc }}'';
              "tls.key" = ''{{ index . "tls.key" | b64enc }}'';
            };
            data = [
              {
                match = {
                  secretKey = "tls.crt";
                  remoteRef = {
                    remoteKey = "wildcard-tls";
                    property = "tls.crt";
                  };
                };
              }
              {
                match = {
                  secretKey = "tls.key";
                  remoteRef = {
                    remoteKey = "wildcard-tls";
                    property = "tls.key";
                  };
                };
              }
            ];
          };
        };

        resources.externalSecrets.wildcard-tls-import = {
          metadata.annotations."argocd.argoproj.io/sync-wave" = "-1";
          spec = {
            refreshPolicy = "CreatedOnce";
            secretStoreRef = {
              name = "onepassword";
              kind = "ClusterSecretStore";
            };
            target = {
              name = "wildcard-tls";
              creationPolicy = "Orphan";
              template = {
                type = "kubernetes.io/tls";
                metadata = {
                  annotations = {
                    "cert-manager.io/alt-names" = "*.${cluster.domain},${cluster.domain}";
                    "cert-manager.io/certificate-name" = "wildcard";
                    "cert-manager.io/common-name" = "";
                    "cert-manager.io/ip-sans" = "";
                    "cert-manager.io/issuer-group" = "";
                    "cert-manager.io/issuer-kind" = "ClusterIssuer";
                    "cert-manager.io/issuer-name" = issuerName;
                    "cert-manager.io/uri-sans" = "";
                  };
                  labels."controller.cert-manager.io/fao" = "true";
                };
              };
            };
            dataFrom = [
              {
                extract = {
                  key = "wildcard-tls";
                  decodingStrategy = "Base64";
                };
              }
            ];
          };
        };

        resources.certificates.wildcard.spec = {
          secretName = "wildcard-tls";
          dnsNames = [
            "*.${cluster.domain}"
            cluster.domain
          ];
          privateKey = {
            algorithm = "ECDSA";
            size = 256;
            rotationPolicy = "Always";
          };
          issuerRef = {
            name = issuerName;
            kind = "ClusterIssuer";
            group = "cert-manager.io";
          };
        };

        resources.pushSecrets.wildcard-tls = {
          metadata.annotations."argocd.argoproj.io/sync-wave" = "1";
          spec = {
            refreshInterval = "1h";
            secretStoreRefs = [
              {
                name = "onepassword";
                kind = "ClusterSecretStore";
              }
            ];
            selector.secret.name = "wildcard-tls";
            template.data = {
              "tls.crt" = ''{{ index . "tls.crt" | b64enc }}'';
              "tls.key" = ''{{ index . "tls.key" | b64enc }}'';
            };
            data = [
              {
                match = {
                  secretKey = "tls.crt";
                  remoteRef = {
                    remoteKey = "wildcard-tls";
                    property = "tls.crt";
                  };
                };
              }
              {
                match = {
                  secretKey = "tls.key";
                  remoteRef = {
                    remoteKey = "wildcard-tls";
                    property = "tls.key";
                  };
                };
              }
            ];
          };
        };

        resources.externalSecrets.cloudflare-dns-api-token = {
          metadata.annotations."argocd.argoproj.io/sync-wave" = "-1";
          spec = {
            secretStoreRef = {
              name = "onepassword";
              kind = "ClusterSecretStore";
            };
            target.name = "cloudflare-dns-api-token";
            data = [
              {
                secretKey = "token";
                remoteRef.key = "cloudflare-dns-api-token/credentials/token";
              }
            ];
          };
        };
      };
    };
}
