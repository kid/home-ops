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
{ lib, ... }:
let
  secretsLib = import ../_secrets-lib.nix { inherit lib; };

  # Prototype for the shared SopsSecret convention
  # (modules/kubernetes/_secrets-lib.nix): proves a real, externally-sourced
  # secret flows local value file -> Nix -> sops-encrypted SopsSecret ->
  # sops-operator -> an in-cluster Secret. Not yet consumed by a
  # ClusterIssuer (ACME DNS-01 is a separate follow-up) — this only
  # exercises the plumbing. Fill the real value locally at
  # secrets/values/cert-manager/cloudflare-dns-api-token/token (gitignored)
  # before running `nix run .#write-manifests` to get a real, non-empty
  # ciphertext.
  cloudflareDnsApiToken = secretsLib.mkSopsSecretYaml {
    namespace = "cert-manager";
    name = "cloudflare-dns-api-token";
    fields = [
      {
        name = "token";
        valuePath = "cert-manager/cloudflare-dns-api-token/token";
      }
    ];
  };
in
{
  den.aspects.cert-manager.k8s-manifests =
    { charts, generators, ... }:
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
