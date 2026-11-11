# Advertises host devices as extended resources (devic.es/<name>), so a pod
# asks for one in resources.limits instead of a hostPath and lands on a node
# that has it. intel-gpu: k3s-prd-0's iGPU VF (den.aspects.i915-sriov.guest's
# /dev/dri/i915-render, not the virtio-gpu render node next to it), mounted
# where VA-API and Plex look first.
_: {
  den.aspects.kubernetes.generic-device-plugin.k8s-manifests =
    { charts, cluster, ... }:
    {
      applications.generic-device-plugin = {
        # The chart hard-codes it, and system-node-critical is only admitted there.
        namespace = "kube-system";

        resources.ciliumNetworkPolicies = with cluster.methods.netpol; {
          generic-device-plugin = mkPolicy { "app.kubernetes.io/name" = "generic-device-plugin"; } {
            ingress = [ (scrapeIngress [ 8080 ]) ];
          };
        };

        helm.releases.generic-device-plugin = {
          chart = charts.squat.generic-device-plugin;
          values = {
            image = {
              # renovate: datasource=docker depName=docker.io/squat/generic-device-plugin
              tag = "0.2.0@sha256:66c8d5c270eb2b721f1064c549b9b7898152a6d2f0163380a5d37dc7636c20ff";
              pullPolicy = "IfNotPresent";
            };
            # It only talks to the kubelet's socket.
            serviceAccount.automount = false;
            devices = [
              {
                name = "intel-gpu";
                groups = [
                  {
                    # Plex, and Frigate later.
                    count = 2;
                    paths = [
                      {
                        path = "/dev/dri/i915-render";
                        mountPath = "/dev/dri/renderD128";
                      }
                    ];
                  }
                ];
              }
            ];
          };
        };
      };
    };
}
