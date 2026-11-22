# Alertmanager → Home Assistant webhooks: HA automations turn critical and
# warning alerts into phone notifications, and Watchdog's heartbeat restarts
# an HA timer that notifies when it stops. Both run on the same cluster, so
# the timer misses an outage that takes HA down too.
#
# The timer and automations are an HA package, mounted at /config/packages
# next to a secrets.yaml with the webhook IDs, which its !secret tags read.
# HA loads it through `homeassistant: packages: !include_dir_named packages`
# in its configuration.yaml (in the volume, added by hand once). Read-only in
# HA's UI.
{ lib, ... }:
let
  # The webhook IDs, generated once by the generated-secrets stack: the
  # Secrets' key -> its fragment.
  webhooks = lib.genAttrs [ "alerts" "watchdog" ] (key: {
    item = "alertmanager-ha-${key}-webhook";
    field = "webhook-id";
    length = 32;
    special = false;
  });
  webhookKeys = lib.attrNames webhooks;
  secretName = key: "alertmanager_${key}_webhook";
  secretTag = key: "!secret ${secretName key}";

  # Only to the phone of the person who runs the cluster.
  notify = "notify.mobile_app_arnauds_iphone";
  timer = "timer.alertmanager_watchdog";
  webhookTrigger = key: {
    trigger = "webhook";
    webhook_id = secretTag key;
    allowed_methods = [ "POST" ];
    # HA's "local" is RFC 1918 and the pod CIDR (172.40.0.0/16) is outside it,
    # so local_only would reject Alertmanager. The random 32-character ID is
    # the webhook's only guard (HA is public through the tunnel).
    local_only = false;
  };
  # One notification per alert group; the resolved one replaces the firing
  # one (Android's tag, iOS's collapse id).
  groupTag = "{{ (trigger.json.commonLabels.alertname ~ '-' ~ (trigger.json.commonLabels.namespace | default(''))) [:64] }}";

  package = {
    timer.alertmanager_watchdog = {
      name = "Alertmanager watchdog";
      duration = "00:15:00";
      restore = true;
      icon = "mdi:heart-pulse";
    };
    automation = [
      {
        id = "alertmanager_watchdog_heartbeat";
        alias = "Alertmanager watchdog heartbeat";
        description = "Alertmanager's Watchdog, every 5 minutes, restarts the 15-minute timer.";
        mode = "restart";
        triggers = [ (webhookTrigger "watchdog") ];
        actions = [
          {
            action = "timer.start";
            target.entity_id = timer;
          }
        ];
      }
      {
        id = "alertmanager_watchdog_lost";
        alias = "Alertmanager watchdog lost";
        description = "No Watchdog from Alertmanager for 15 minutes.";
        triggers = [
          {
            trigger = "event";
            event_type = "timer.finished";
            event_data.entity_id = timer;
          }
        ];
        actions = [
          {
            action = notify;
            data = {
              title = "Alertmanager heartbeat lost";
              message = "No Watchdog from Alertmanager for 15 minutes.";
              data.push.interruption-level = "time-sensitive";
            };
          }
        ];
      }
      {
        id = "alertmanager_alerts";
        alias = "Alertmanager alerts";
        description = "Critical and warning alerts from Alertmanager, one notification per alert group.";
        mode = "queued";
        triggers = [ (webhookTrigger "alerts") ];
        actions = [
          {
            action = notify;
            data = {
              title = "[{{ trigger.json.status | upper }}] {{ trigger.json.commonLabels.alertname }} ({{ trigger.json.alerts | length }})";
              message = "{{ trigger.json.commonAnnotations.summary | default(trigger.json.commonAnnotations.description, true) | default(trigger.json.commonLabels.namespace, true) | default('', true) }}";
              data = {
                tag = groupTag;
                apns_headers.apns-collapse-id = groupTag;
                push.interruption-level = "{{ 'time-sensitive' if trigger.json.status == 'firing' and trigger.json.commonLabels.severity == 'critical' else 'active' }}";
              };
            };
          }
        ];
      }
    ];
  };

  # JSON is YAML; the tags go in unquoted.
  packageYaml =
    package
    |> builtins.toJSON
    |> builtins.replaceStrings (map (k: ''"${secretTag k}"'') webhookKeys) (map secretTag webhookKeys);
in
{
  den.aspects.kubernetes.home-assistant.alertmanager.generated-secrets = _: lib.attrValues webhooks;

  den.aspects.kubernetes.home-assistant.alertmanager.k8s-manifests =
    { cluster, ... }:
    let
      secret = "alertmanager-homeassistant";
      # VMAlertmanager mounts spec.secrets at /etc/vm/secrets/<name>/.
      webhooksDir = "/etc/vm/secrets/${secret}";
      port = 8123;
      haLabels."app.kubernetes.io/name" = "home-assistant";
      alertmanagerLabels."app.kubernetes.io/name" = "vmalertmanager";

      # Both webhook IDs into a Secret named `secret`, templated per key.
      generated = lib.mapAttrs (_: cluster.methods.mkGeneratedSecret) webhooks;
      mkExternalSecret = templateData: {
        inherit (generated.alerts) secretStoreRef;
        target = {
          name = secret;
          template.data = templateData;
        };
        data = lib.mapAttrsToList (key: g: builtins.head g.data // { secretKey = key; }) generated;
      };
    in
    {
      applications.home-assistant = {
        # The external-secrets webhook admits the ExternalSecret.
        flux.dependsOn = [ "external-secrets-config" ];

        resources = {
          configMaps.${secret}.data."alertmanager.yaml" = packageYaml;
          externalSecrets.${secret}.spec = mkExternalSecret {
            "secrets.yaml" =
              webhookKeys
              |> map (key: lib.nameValuePair (secretName key) "{{ .${key} }}")
              |> lib.listToAttrs
              |> builtins.toJSON;
          };

          deployments.home-assistant.spec.template = {
            # HA reads the package only when it starts.
            metadata.annotations."checksum/alertmanager-package" = builtins.hashString "sha256" packageYaml;
            spec = {
              containers.home-assistant.volumeMounts."/config/packages" = {
                name = "packages";
                readOnly = true;
              };
              volumes.packages.projected.sources = [
                { configMap.name = secret; }
                { secret.name = secret; }
              ];
            };
          };

          ciliumNetworkPolicies.home-assistant-alertmanager =
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
        };
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

        # The webhook URLs Alertmanager reads.
        resources.externalSecrets.${secret}.spec = mkExternalSecret (
          lib.genAttrs webhookKeys (
            key: "http://home-assistant.home-assistant.svc:${toString port}/api/webhook/{{ .${key} }}"
          )
        );

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
