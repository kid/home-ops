# cert-manager. Installed so Cilium can issue Hubble's mTLS certs through it
# instead of Helm's own genCA/genSignedCert, which re-randomizes on every
# render and made manifests/prd/cilium's certs non-idempotent.
#
# ClusterIssuer/Certificate aren't core Kubernetes types, so nixidy has no
# built-in typed options for them — _crds.nix (generated, see its own
# header) provides them, so the self-signed CA + ClusterIssuer chain below
# is real Nix, not embedded YAML.
_: {
  den.aspects.cert-manager.k8s-manifests =
    { charts, ... }:
    {
      nixidy.applicationImports = [ ./_crds.nix ];

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
      };
    };
}
