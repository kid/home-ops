# cert-manager. Installed so Cilium can issue Hubble's mTLS certs through it
# (modules/kubernetes/cilium/hubble-tls.nix) instead of Helm's own
# genCA/genSignedCert, which re-randomizes on every render and made
# manifests/prd/cilium's certs non-idempotent.
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
        };
      };
  };
}
