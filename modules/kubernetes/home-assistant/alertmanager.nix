# Alertmanager → Home Assistant webhooks: HA automations turn critical and
# warning alerts into phone notifications, and Watchdog's heartbeat restarts
# an HA timer that notifies when it stops. Both run on the same cluster, so
# the timer misses an outage that takes HA down too.
_: {
  den.aspects.kubernetes.home-assistant.alertmanager.k8s-manifests =
    { cluster, ... }:
    let
      secret = "alertmanager-homeassistant";
      # VMAlertmanager mounts spec.secrets at /etc/vm/secrets/<name>/.
      webhooksDir = "/etc/vm/secrets/${secret}";
      port = 8123;
      haLabels."app.kubernetes.io/name" = "home-assistant";
      alertmanagerLabels."app.kubernetes.io/name" = "vmalertmanager";
    in
    {
      applications.home-assistant.resources.ciliumNetworkPolicies.home-assistant-alertmanager =
        with cluster.methods.netpol;
        mkPolicy haLabels {
          ingress = [
            {
              fromEndpoints = [
                {
                  matchLabels = alertmanagerLabels // {
                    "k8s:io.kubernetes.pod.namespace" = "monitoring";
                  };
                }
              ];
              toPorts = tcp [ port ];
            }
          ];
        };

      applications.victoria-metrics = {
        # The external-secrets webhook admits the ExternalSecret.
        flux.dependsOn = [ "external-secrets-config" ];

        resources.ciliumNetworkPolicies.vmalertmanager-home-assistant =
          with cluster.methods.netpol;
          mkPolicy alertmanagerLabels {
            egress = [
              {
                toEndpoints = [
                  {
                    matchLabels = haLabels // {
                      "k8s:io.kubernetes.pod.namespace" = "home-assistant";
                    };
                  }
                ];
                toPorts = tcp [ port ];
              }
            ];
          };

        # 1Password holds only the webhook IDs, which HA's automations set.
        resources.externalSecrets.${secret}.spec = {
          secretStoreRef = {
            name = "onepassword";
            kind = "ClusterSecretStore";
          };
          target = {
            name = secret;
            template.data = {
              alerts = "http://home-assistant.home-assistant.svc:${toString port}/api/webhook/{{ .alerts }}";
              watchdog = "http://home-assistant.home-assistant.svc:${toString port}/api/webhook/{{ .watchdog }}";
            };
          };
          data = [
            {
              secretKey = "alerts";
              remoteRef.key = "${secret}/alerts-webhook-id";
            }
            {
              secretKey = "watchdog";
              remoteRef.key = "${secret}/watchdog-webhook-id";
            }
          ];
        };

        helm.releases.victoria-metrics.values.alertmanager = {
          spec.secrets = [ secret ];

          # Lists replace the chart's, so its blackhole receiver is restated.
          config = {
            route = {
              receiver = "blackhole";
              group_by = [
                "alertname"
                "namespace"
              ];
              routes = [
                {
                  matchers = [ ''alertname="Watchdog"'' ];
                  receiver = "ha-watchdog";
                  group_wait = "0s";
                  group_interval = "1m";
                  repeat_interval = "5m";
                }
                {
                  matchers = [ ''severity=~"critical|warning"'' ];
                  receiver = "homeassistant";
                }
              ];
            };
            inhibit_rules = [
              {
                source_matchers = [ ''severity="critical"'' ];
                target_matchers = [ ''severity="warning"'' ];
                equal = [
                  "alertname"
                  "namespace"
                ];
              }
            ];
            receivers = [
              { name = "blackhole"; }
              {
                name = "homeassistant";
                webhook_configs = [
                  {
                    url_file = "${webhooksDir}/alerts";
                    send_resolved = true;
                  }
                ];
              }
              {
                name = "ha-watchdog";
                webhook_configs = [
                  {
                    url_file = "${webhooksDir}/watchdog";
                    send_resolved = false;
                  }
                ];
              }
            ];
          };
        };
      };
    };
}
