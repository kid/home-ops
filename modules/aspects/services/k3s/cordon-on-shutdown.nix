# Cordons the node as soon as logind announces a shutdown (PrepareForShutdown,
# the signal the kubelet's graceful node shutdown also waits on), and
# uncordons it at boot. Without it, the scheduler sends a pod the kubelet
# stopped during the shutdown straight back to the node when the pod
# tolerates node.kubernetes.io/not-ready (cilium-operator does), the kubelet
# rejects it with NodeShutdown, and the ReplicaSet makes another, a few per
# second, until k3s stops (kubernetes/kubernetes#139246). Cordoned, the node
# gets node.kubernetes.io/unschedulable, which those pods don't tolerate.
#
# The kubelet's own credentials: NodeRestriction lets a node set its own
# spec.unschedulable and annotations (not its taints). The annotation marks
# a cordon this unit made, so boot never undoes a manual one. A cancelled
# shutdown leaves the node cordoned until the next boot.
_: {
  den.aspects.k3s.cordon-on-shutdown.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      node = config.networking.hostName;
      annotation = "home-ops.dev/cordoned-on-shutdown";

      kc = ''
        kc() {
          k3s kubectl --kubeconfig=/var/lib/rancher/k3s/agent/kubelet.kubeconfig --request-timeout=10s "$@"
        }
      '';

      # Run under its own delay inhibitor lock: the shutdown waits for the
      # cordon, then goes on as soon as this exits, whatever the result.
      cordonOnShutdown = pkgs.writeShellScript "cordon-on-shutdown" ''
        ${kc}
        cordon() {
          unschedulable=$(kc get node ${node} -o jsonpath='{.spec.unschedulable}') || return
          [ "$unschedulable" = true ] && return
          kc patch node ${node} --type=merge \
            -p '{"metadata":{"annotations":{"${annotation}":"true"}},"spec":{"unschedulable":true}}'
        }

        while read -r line; do
          [[ $line == *".PrepareForShutdown (true,)" ]] || continue
          cordon || echo "cordon failed" >&2
          exit 0
        done < <(gdbus monitor --system --dest org.freedesktop.login1 --object-path /org/freedesktop/login1)
        echo "gdbus monitor exited" >&2
        exit 1
      '';
    in
    {
      systemd.services.k3s-cordon-on-shutdown = {
        description = "Cordon the k3s node on shutdown, uncordon it at boot";
        after = [ "k3s.service" ];
        wantedBy = [ "multi-user.target" ];
        path = [
          config.services.k3s.package
          (lib.getBin pkgs.glib)
          pkgs.jq
        ];
        serviceConfig = {
          Restart = "always";
          RestartSec = 5;
        };
        script = ''
          ${kc}
          uncordon() {
            json=$(kc get node ${node} -o json) || return
            jq -e '.metadata.annotations | has("${annotation}")' <<<"$json" >/dev/null || return 0
            kc patch node ${node} --type=merge \
              -p '{"metadata":{"annotations":{"${annotation}":null}},"spec":{"unschedulable":false}}'
          }

          # Taken before the boot uncordon, which waits for the API.
          systemd-inhibit --what=shutdown --mode=delay --who=k3s-cordon-on-shutdown \
            --why="Cordon the node before the kubelet stops its pods" ${cordonOnShutdown} &
          inhibitor=$!

          until uncordon; do sleep 5; done
          echo "Watching for shutdowns"
          # Fails, and restarts the unit, only when the monitor died. After a
          # cordon, exiting would restart the unit and take the lock again.
          wait "$inhibitor"
          exec sleep infinity
        '';
      };
    };
}
