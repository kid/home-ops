# Frigate, the NVR for the two Reolink cameras: decodes on k3s-prd-0's iGPU
# VF (VA-API) and detects with OpenVINO on it, sharing the VF with Plex.
# Recordings and snapshots go to a node0 NVMe dataset over NFS (the
# nfs-exports quirk); its database and config sit on the kopiur-backed volume.
# The ConfigMap's config.yml is copied over /config/config.yml on every start,
# so edits made in the UI don't survive a restart: change them here.
{ config, lib, ... }:
let
  name = "frigate";
  namespace = "home-assistant";
  labels."app.kubernetes.io/name" = name;
  port = 5000;
  rtspPort = 8554;
  mqttPort = 8883;
  caDir = "/etc/cluster-ca";
  nfsPath = "/srv/frigate";
  # renovate: datasource=docker depName=ghcr.io/blakeblackshear/frigate
  tag = "0.18.2@sha256:fd60f99ffd4eb6c42360ed4e14953e270586f239309ab3983e55b2e97ffac09a";

  # Frigate camera name → address. Each camera's stream login is the
  # reolink-<name> 1Password item.
  cameras = {
    doorbell = config.den.devices.doorbell.address;
    litters = config.den.devices."litters camera".address;
  };
  # http-flv (80), Frigate's recommended stream for Reolinks up to 5MP, and
  # RTSP (554), the fallback.
  cameraPorts = [
    80
    554
  ];

  # A camera's login env vars, from its own item (the frigate-cameras Secret).
  credEnv = cam: field: "FRIGATE_${lib.toUpper cam}_${field}";

  # Reolink's http-flv stream. Frigate fills the {FRIGATE_*} placeholders
  # with str.format, so the URL holds no other braces.
  flv =
    cam: stream:
    "ffmpeg:http://${cameras.${cam}}/flv?port=1935&app=bcs&stream=channel0_${stream}.bcs&user={${credEnv cam "USER"}}&password={${credEnv cam "PASSWORD"}}";

  frigateConfig = {
    mqtt = {
      host = "mosquitto.${namespace}.svc";
      port = mqttPort;
      user = name;
      password = "{FRIGATE_MQTT_PASSWORD}";
      tls_ca_certs = "${caDir}/ca.crt";
    };
    detectors.ov = {
      type = "openvino";
      device = "GPU";
    };
    # The bundled SSDLite MobileNet v2 IR model.
    model = {
      width = 300;
      height = 300;
      input_tensor = "nhwc";
      input_pixel_format = "bgr";
      path = "/openvino-model/ssdlite_mobilenet_v2.xml";
      labelmap_path = "/openvino-model/coco_91cl_bkgr.txt";
    };
    ffmpeg.hwaccel_args = "preset-vaapi";
    # The VF, not Incus's virtio-gpu.
    telemetry.stats.intel_gpu_device = "/dev/dri/renderD128";
    record = {
      enabled = true;
      continuous.days = 0;
      motion.days = 0;
      alerts.retain = {
        days = 14;
        mode = "motion";
      };
      detections.retain = {
        days = 14;
        mode = "motion";
      };
    };
    snapshots = {
      enabled = true;
      retain.default = 14;
    };
    go2rtc.streams = lib.concatMapAttrs (cam: _: {
      ${cam} = [ "${flv cam "main"}#video=copy#audio=copy#audio=opus" ];
      "${cam}_sub" = [ (flv cam "ext") ];
    }) cameras;
    cameras =
      lib.recursiveUpdate
        (lib.mapAttrs (cam: _: {
          ffmpeg.inputs = [
            {
              path = "rtsp://127.0.0.1:${toString rtspPort}/${cam}";
              input_args = "preset-rtsp-restream";
              roles = [ "record" ];
            }
            {
              path = "rtsp://127.0.0.1:${toString rtspPort}/${cam}_sub";
              input_args = "preset-rtsp-restream";
              roles = [ "detect" ];
            }
          ];
        }) cameras)
        {
          doorbell.objects.track = [ "person" ];
          litters = {
            objects.track = [ "cat" ];
            review.alerts.labels = [ "cat" ];
          };
        };
  };
in
{
  # RouterOS access this app needs — see modules/den/quirks/firewall.nix.
  den.aspects.kubernetes.home-assistant.frigate.firewall = { cluster, ... }: [
    {
      inherit (cluster) network;
      forward =
        cameras
        |> lib.mapAttrsToList (
          cam: address:
          map (p: {
            action = "accept";
            dst_address = address;
            dst_port = p;
            protocol = "tcp";
            comment = "Allow Frigate on K3s to reach the ${cam} camera on ${toString p}";
          }) cameraPorts
        )
        |> lib.concatLists;
    }
  ];

  # Its recordings and snapshots: a node0 dataset, exported to the nodes.
  den.aspects.kubernetes.home-assistant.frigate.nfs-exports = _: [
    {
      dataset = "zroot/frigate";
      path = nfsPath;
      properties = {
        recordsize = "1M";
        quota = "200G";
      };
    }
  ];

  den.aspects.kubernetes.home-assistant.frigate.k8s-manifests =
    { cluster, ... }:
    let
      hostname = cluster.methods.mkAppHostname name;
    in
    {
      applications.frigate = {
        inherit namespace;
        flux.dependsOn = [
          # The kopiur webhook admits the backup objects.
          "kopiur-config"
          # Its MQTT password Secret.
          "mosquitto"
          # The onepassword store, for the cameras' logins.
          "external-secrets-config"
        ];

        imports = [
          (cluster.methods.mkOidcAuth {
            inherit name hostname;
            httpRouteName = name;
            group = "admins";
          })
        ];

        resources =
          cluster.methods.mkKopiurBackup {
            inherit name;
            # Frigate runs as root and owns /config.
            uid = 0;
            storage = "5Gi";
            ignore = [ "/model_cache" ];
          }
          // {
            externalSecrets.frigate-cameras.spec = {
              secretStoreRef = {
                name = "onepassword";
                kind = "ClusterSecretStore";
              };
              target.name = "frigate-cameras";
              data =
                cameras
                |> lib.attrNames
                |> lib.concatMap (
                  cam:
                  map
                    (field: {
                      secretKey = "${cam}-${field}";
                      remoteRef.key = "reolink-${cam}/${field}";
                    })
                    [
                      "username"
                      "password"
                    ]
                );
            };

            configMaps.${name}.data."config.yml" = builtins.toJSON frigateConfig;

            ciliumNetworkPolicies.${name} =
              with cluster.methods.netpol;
              mkPolicy labels {
                ingress = [
                  (gatewayIngress port)
                  (fromPods { "app.kubernetes.io/name" = "home-assistant"; } [
                    port
                    rtspPort
                  ])
                ];
                egress = [
                  (toPods { "app.kubernetes.io/name" = "mosquitto"; } [ mqttPort ])
                  {
                    toCIDR = cameras |> lib.attrValues |> map (a: "${a}/32");
                    toPorts = tcp cameraPorts;
                  }
                ];
              };

            deployments.${name}.spec = {
              strategy.type = "Recreate";
              selector.matchLabels = labels;
              template = {
                metadata = {
                  inherit labels;
                  annotations."checksum/config" = frigateConfig |> builtins.toJSON |> builtins.hashString "sha256";
                };
                spec = {
                  automountServiceAccountToken = false;
                  # No runAsNonRoot or read-only root: the image's s6-overlay
                  # and nginx run as root.
                  securityContext.seccompProfile.type = "RuntimeDefault";
                  # Frigate migrates and rewrites its config file, so it
                  # can't be the read-only ConfigMap mount itself.
                  initContainers.config = {
                    image = "ghcr.io/blakeblackshear/frigate:${tag}";
                    command = [
                      "cp"
                      "/etc/frigate/config.yml"
                      "/config/config.yml"
                    ];
                    volumeMounts = {
                      "/etc/frigate".name = "frigate-config";
                      "/config".name = "config";
                    };
                  };
                  containers.${name} = {
                    image = "ghcr.io/blakeblackshear/frigate:${tag}";
                    env = {
                      FRIGATE_MQTT_PASSWORD.valueFrom.secretKeyRef = {
                        name = "mosquitto-${name}";
                        key = "password";
                      };
                    }
                    // lib.concatMapAttrs (cam: _: {
                      ${credEnv cam "USER"}.valueFrom.secretKeyRef = {
                        name = "frigate-cameras";
                        key = "${cam}-username";
                      };
                      ${credEnv cam "PASSWORD"}.valueFrom.secretKeyRef = {
                        name = "frigate-cameras";
                        key = "${cam}-password";
                      };
                    }) cameras;
                    ports = {
                      http.containerPort = port;
                      rtsp.containerPort = rtspPort;
                    };
                    # OpenVINO compiles the model for the GPU on first start.
                    startupProbe = {
                      httpGet = {
                        path = "/api/version";
                        port = "http";
                      };
                      periodSeconds = 10;
                      failureThreshold = 60;
                    };
                    livenessProbe.httpGet = {
                      path = "/api/version";
                      port = "http";
                    };
                    resources = {
                      requests = {
                        cpu = "500m";
                        memory = "1Gi";
                      };
                      limits = {
                        memory = "4Gi";
                        # Its share of the VF, which also pins it to k3s-prd-0.
                        "devic.es/intel-gpu" = 1;
                      };
                    };
                    volumeMounts = {
                      "/config".name = "config";
                      "/media/frigate".name = "media";
                      ${caDir}.name = "cluster-ca";
                      "/dev/shm".name = "shm";
                      "/tmp/cache".name = "cache";
                    };
                  };
                  volumes = {
                    config.persistentVolumeClaim.claimName = name;
                    frigate-config.configMap.name = name;
                    # No mkNfsScaler: k3s-prd-0 runs on node0, so it never
                    # outlives its NFS server.
                    media.nfs = {
                      server = cluster.methods.mediaNfsServer;
                      path = nfsPath;
                    };
                    cluster-ca.configMap.name = "cluster-ca";
                    shm.emptyDir = {
                      medium = "Memory";
                      sizeLimit = "256Mi";
                    };
                    # Recording segments are staged here before they move to
                    # /media/frigate, as Frigate's docs advise.
                    cache.emptyDir = {
                      medium = "Memory";
                      sizeLimit = "1Gi";
                    };
                  };
                };
              };
            };

            services.${name}.spec = {
              selector = labels;
              ports = {
                http = {
                  inherit port;
                  targetPort = "http";
                };
                rtsp = {
                  port = rtspPort;
                  targetPort = "rtsp";
                };
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
              rules = [
                {
                  backendRefs = [ { inherit name port; } ];
                  # Live view (MSE over WebSocket) and exports outlast
                  # Envoy's 15s default.
                  timeouts.request = "0s";
                }
              ];
            };
          };
      };
    };
}
