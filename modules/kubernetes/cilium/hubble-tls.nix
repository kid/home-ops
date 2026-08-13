# Self-signed CA + ClusterIssuer that cert-manager uses to sign Hubble's
# mTLS certs, referenced by modules/kubernetes/cilium/default.nix's
# hubble.tls.auto.certManagerIssuerRef (name: hubble-ca-issuer). Standard
# cert-manager self-signed-root bootstrap: a selfSigned ClusterIssuer signs
# one CA Certificate, then a second ClusterIssuer signs everything else off
# that CA's secret. Lives under applications.cert-manager (not
# applications.cilium) since these are cert-manager.io CRs that must apply
# after cert-manager's own CRDs/webhook exist — mirrors how
# modules/kubernetes/cilium/bgp.nix contributes extra yamls to a sibling
# application's k8s-manifests scope.
_: {
  den.aspects.cilium-hubble-tls.k8s-manifests = {
    applications.cert-manager.yamls = [
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
}
