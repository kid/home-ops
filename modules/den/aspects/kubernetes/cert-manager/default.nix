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
            "Issuer"
          ];
          extraOpts = [
            "--set"
            "crds.enabled=true"
          ];
        })
      ];

      applications.cert-manager = {
        namespace = "cert-manager";

        resources.ciliumNetworkPolicies =
          with cluster.methods.netpol;
          let
            app = name: {
              "app.kubernetes.io/name" = name;
              "app.kubernetes.io/instance" = "cert-manager";
            };
          in
          {
            cert-manager = mkPolicy (app "cert-manager") {
              ingress = [ (scrapeIngress [ 9402 ]) ];
              egress = [
                apiserverEgress
                (fqdnEgress
                  [
                    "acme-v02.api.letsencrypt.org"
                    "api.cloudflare.com"
                  ]
                  [ 443 ]
                )
                {
                  toEntities = [ "world" ];
                  toPorts = tcpUdp [ 53 ];
                }
              ];
            };
            cert-manager-cainjector = mkPolicy (app "cainjector") {
              ingress = [ (scrapeIngress [ 9402 ]) ];
              egress = [ apiserverEgress ];
            };
            cert-manager-webhook = mkPolicy (app "webhook") {
              ingress = [
                (webhookIngress 10250)
                (scrapeIngress [ 9402 ])
              ];
              egress = [ apiserverEgress ];
            };
            cert-manager-startupapicheck = mkPolicy (app "startupapicheck") {
              egress = [ apiserverEgress ];
            };
          };

        # Before envoy-gateway, whose Gateway serves the wildcard cert below.
        annotations."argocd.argoproj.io/sync-wave" = "-2";

        helm.releases.cert-manager = {
          chart = charts.jetstack.cert-manager;
          values = {
            crds.enabled = true;
            replicaCount = 1;
            prometheus.servicemonitor.enabled = true;
            resources = {
              requests = {
                cpu = "10m";
                memory = "64Mi";
              };
              limits.memory = "192Mi";
            };
            webhook.resources = {
              requests = {
                cpu = "10m";
                memory = "64Mi";
              };
              limits.memory = "128Mi";
            };
            startupapicheck.resources.requests = {
              cpu = "10m";
              memory = "64Mi";
            };
            cainjector.resources = {
              requests = {
                cpu = "10m";
                memory = "128Mi";
              };
              limits.memory = "384Mi";
            };
          };
        };

        # Standard cert-manager self-signed-root bootstrap: a selfSigned
        # ClusterIssuer signs the cluster CA Certificate, then the cluster-ca
        # ClusterIssuer signs every in-cluster certificate (Hubble mTLS via
        # modules/den/aspects/kubernetes/cilium/default.nix, backend TLS for
        # Envoy) off that CA's secret. trust-manager publishes the CA as the
        # cluster-ca ConfigMap. Certificate's namespace defaults to this
        # application's own namespace (cert-manager).
        resources.clusterIssuers.selfsigned-issuer.spec.selfSigned = { };

        # 10-year CA: cert-manager's 90d default would rotate the key mid-life
        # of the leaf certs it signs. rotationPolicy Never keeps the key on
        # renewal, so leaves signed before it still verify.
        resources.certificates.cluster-ca.spec = {
          isCA = true;
          commonName = "cluster-ca";
          secretName = "cluster-ca";
          duration = "87600h";
          privateKey = {
            algorithm = "ECDSA";
            size = 256;
            rotationPolicy = "Never";
          };
          issuerRef = {
            name = "selfsigned-issuer";
            kind = "ClusterIssuer";
            group = "cert-manager.io";
          };
        };

        resources.clusterIssuers.cluster-ca.spec.ca.secretName = "cluster-ca";

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

        # In envoy-gateway's namespace: a Gateway reads its certificateRefs
        # from its own namespace unless a ReferenceGrant allows otherwise.
        resources.certificates.wildcard = {
          metadata.namespace = "envoy-gateway-system";
          spec = {
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
