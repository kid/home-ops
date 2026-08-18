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
  den.aspects.cert-manager.k8s-manifests =
    {
      charts,
      generators,
      cluster,
      ...
    }:
    let
      # Prototype for the shared SopsSecret convention
      # (den.clusters.<name>.methods.mkSopsSecret, set by
      # modules/kubernetes/sops-operator/default.nix): proves a real,
      # externally-sourced secret flows committed ciphertext ->
      # write-manifests -> sops-encrypted SopsSecret -> sops-operator -> an
      # in-cluster Secret. Not yet consumed by a ClusterIssuer (ACME DNS-01
      # is a separate follow-up) — this only exercises the plumbing. To
      # provide the real value (namespace/name below must match the file
      # path — that's how write-manifests finds it):
      #   mkdir -p secrets/clusters/prd/cert-manager
      #   echo '{"token": "<value>"}' > secrets/clusters/prd/cert-manager/cloudflare-dns-api-token.sops.json
      #   sops -e -i --input-type json --output-type json \
      #     secrets/clusters/prd/cert-manager/cloudflare-dns-api-token.sops.json
      # then commit it and run `nix run .#write-manifests`.
      cloudflareDnsApiToken = cluster.methods.mkSopsSecret {
        namespace = "cert-manager";
        name = "cloudflare-dns-api-token";
      };
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
        createNamespace = true;

        helm.releases.cert-manager = {
          chart = charts.jetstack.cert-manager;
          values = {
            crds.enabled = true;
            replicaCount = 1;
          };
        };

        # Standard cert-manager self-signed-root bootstrap: a selfSigned
        # ClusterIssuer signs one CA Certificate, then hubble-ca-issuer
        # (referenced by modules/kubernetes/cilium/default.nix's
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

        yamls = [ cloudflareDnsApiToken ];
      };
    };
}
