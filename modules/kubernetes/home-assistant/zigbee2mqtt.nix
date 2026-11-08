# Zigbee2MQTT, replacing HAOS's add-on: drives the UZG-01's coordinator over
# TCP and publishes to Mosquitto over TLS. Its data (configuration.yaml with
# the network key, database.db, coordinator_backup.json, state.json) is
# imported once into the kopiur-backed volume at the cutover. The env vars
# override what the imported configuration.yaml says about MQTT, the serial
# port and the frontend.
#
# `stage` walks the cutover:
# - "vm": the add-on still runs; no volume (a WaitForFirstConsumer claim with
#   no pod stays Pending, which keeps the Flux Kustomization unready).
# - "import": the volume and its backups exist, still scaled to zero: the
#   add-on is stopped and its data copied in by a one-off pod.
# - "live": scaled to one. Never before the import: a Zigbee2MQTT whose
#   network settings don't match the coordinator's re-forms the network and
#   drops every device, and two must never drive the coordinator at once.
{ config, lib, ... }:
let
  stage = "live";

  name = "zigbee2mqtt";
  namespace = "home-assistant";
  labels."app.kubernetes.io/name" = name;
  port = 8080;
  uid = 1000;
  # Same version as the add-on it replaces, so the imported database isn't
  # migrated at the cutover.
  # renovate: datasource=docker depName=ghcr.io/koenkk/zigbee2mqtt
  tag = "2.14.3@sha256:fb4a6b0f6868ad1cd6a9996479802b2420e599c3463b62bbff8c8cd9a908f43a";
  coordinator = config.den.devices.uzg-01.address;
  # The UZG-01's uart_tcp server (esphome/uzg-01.yaml).
  coordinatorPort = 6638;
  mqttPort = 8883;
  caDir = "/etc/cluster-ca";
in
{
  # RouterOS access this app needs — see modules/den/quirks/firewall.nix.
  den.aspects.kubernetes.home-assistant.zigbee2mqtt.firewall = { cluster, ... }: [
    {
      inherit (cluster) network;
      forward = [
        {
          action = "accept";
          dst_address = coordinator;
          dst_port = coordinatorPort;
          protocol = "tcp";
          comment = "Allow Zigbee2MQTT on K3s to reach the UZG-01 coordinator";
        }
      ];
    }
  ];

  den.aspects.kubernetes.home-assistant.zigbee2mqtt.k8s-manifests =
    { cluster, ... }:
    let
      hostname = cluster.methods.mkAppHostname name;
    in
    {
      applications.zigbee2mqtt = {
        inherit namespace;
        flux.dependsOn = [
          # The kopiur webhook admits the backup objects.
          "kopiur-config"
          # Its MQTT password Secret.
          "mosquitto"
        ];

        imports = [
          (cluster.methods.mkOidcAuth {
            inherit name hostname;
            httpRouteName = name;
            group = "admins";
          })
        ];

        resources =
          lib.optionalAttrs (stage != "vm") (
            cluster.methods.mkKopiurBackup {
              inherit name uid;
            }
          )
          // {
            ciliumNetworkPolicies.${name} =
              with cluster.methods.netpol;
              mkPolicy labels {
                ingress = [ (gatewayIngress port) ];
                egress = [
                  (toPods { "app.kubernetes.io/name" = "mosquitto"; } [ mqttPort ])
                  {
                    toCIDR = [ "${coordinator}/32" ];
                    toPorts = tcp [ coordinatorPort ];
                  }
                  # The OTA index and firmware images.
                  (worldEgress [ 443 ])
                ];
              };

            deployments.${name}.spec = {
              replicas = if stage == "live" then 1 else 0;
              strategy.type = "Recreate";
              selector.matchLabels = labels;
              template = {
                metadata = { inherit labels; };
                spec = {
                  automountServiceAccountToken = false;
                  securityContext = {
                    runAsNonRoot = true;
                    runAsUser = uid;
                    runAsGroup = uid;
                    fsGroup = uid;
                    fsGroupChangePolicy = "OnRootMismatch";
                    seccompProfile.type = "RuntimeDefault";
                  };
                  containers.${name} = {
                    image = "ghcr.io/koenkk/zigbee2mqtt:${tag}";
                    env =
                      lib.mapAttrs (_: value: { inherit value; }) {
                        ZIGBEE2MQTT_CONFIG_MQTT_SERVER = "mqtts://mosquitto.${namespace}.svc:${toString mqttPort}";
                        ZIGBEE2MQTT_CONFIG_MQTT_USER = name;
                        ZIGBEE2MQTT_CONFIG_MQTT_CA = "${caDir}/ca.crt";
                        ZIGBEE2MQTT_CONFIG_SERIAL_PORT = "tcp://${coordinator}:${toString coordinatorPort}";
                        ZIGBEE2MQTT_CONFIG_SERIAL_ADAPTER = "zstack";
                        ZIGBEE2MQTT_CONFIG_FRONTEND_ENABLED = "true";
                        ZIGBEE2MQTT_CONFIG_FRONTEND_PORT = toString port;
                        # The device links Home Assistant shows.
                        ZIGBEE2MQTT_CONFIG_FRONTEND_URL = "https://${hostname}";
                        ZIGBEE2MQTT_CONFIG_HOMEASSISTANT_ENABLED = "true";
                        # stdout only, as JSON: no log files on the volume.
                        ZIGBEE2MQTT_CONFIG_ADVANCED_LOG_OUTPUT = ''["console"]'';
                        ZIGBEE2MQTT_CONFIG_ADVANCED_LOG_CONSOLE_JSON = "true";
                      }
                      // {
                        ZIGBEE2MQTT_CONFIG_MQTT_PASSWORD.valueFrom.secretKeyRef = {
                          name = "mosquitto-${name}";
                          key = "password";
                        };
                      };
                    ports.http.containerPort = port;
                    # The frontend only serves once the coordinator and MQTT
                    # are connected.
                    startupProbe = {
                      httpGet = {
                        path = "/";
                        port = "http";
                      };
                      failureThreshold = 30;
                    };
                    livenessProbe.httpGet = {
                      path = "/";
                      port = "http";
                    };
                    securityContext = {
                      allowPrivilegeEscalation = false;
                      readOnlyRootFilesystem = true;
                      capabilities.drop = [ "ALL" ];
                    };
                    resources = {
                      requests = {
                        cpu = "20m";
                        memory = "192Mi";
                      };
                      limits.memory = "512Mi";
                    };
                    volumeMounts = {
                      "/app/data".name = "data";
                      ${caDir}.name = "cluster-ca";
                      "/tmp".name = "tmp";
                    };
                  };
                  volumes = {
                    data.persistentVolumeClaim.claimName = name;
                    cluster-ca.configMap.name = "cluster-ca";
                    tmp.emptyDir = { };
                  };
                };
              };
            };

            services.${name}.spec = {
              selector = labels;
              ports.http = {
                inherit port;
                targetPort = "http";
              };
            };

            httpRoutes.${name}.spec = {
              parentRefs = [
                {
                  group = "gateway.networking.k8s.io";
                  kind = "Gateway";
                  name = "apps";
                  namespace = "envoy-gateway-system";
                  sectionName = "https";
                }
              ];
              hostnames = [ hostname ];
              rules = [ { backendRefs = [ { inherit name port; } ]; } ];
            };
          };
      };
    };
}
