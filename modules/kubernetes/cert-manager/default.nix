# cert-manager. Installed so Cilium can issue Hubble's mTLS certs through it
# instead of Helm's own genCA/genSignedCert, which re-randomizes on every
# render and made manifests/prd/cilium's certs non-idempotent.
#
# The self-signed CA + ClusterIssuer chain below is the standard
# cert-manager self-signed-root bootstrap: a selfSigned ClusterIssuer signs
# one CA Certificate, then hubble-ca-issuer (referenced by modules/
# kubernetes/cilium/default.nix's hubble.tls.auto.certManagerIssuerRef)
# signs everything else off that CA's secret.
_: {
  den.aspects.cert-manager = {
    k8s-manifests =
      { charts, ... }:
      {
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

          yamls = [
            ''
              apiVersion: cert-manager.io/v1
              kind: ClusterIssuer
              metadata:
                name: selfsigned-issuer
              spec:
                selfSigned: {}
            ''
            ''
              apiVersion: cert-manager.io/v1
              kind: Certificate
              metadata:
                name: hubble-ca
                namespace: cert-manager
              spec:
                isCA: true
                commonName: hubble-ca
                secretName: hubble-ca-secret
                privateKey:
                  algorithm: ECDSA
                  size: 256
                issuerRef:
                  name: selfsigned-issuer
                  kind: ClusterIssuer
                  group: cert-manager.io
            ''
            ''
              apiVersion: cert-manager.io/v1
              kind: ClusterIssuer
              metadata:
                name: hubble-ca-issuer
              spec:
                ca:
                  secretName: hubble-ca-secret
            ''
          ];
        };
      };
  };
}
