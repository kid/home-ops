# Home Assistant, moved from the HAOS VM on the Servers VLAN: its /config was
# imported once into the kopiur-backed volume.
#
# HA has its own login. The Cloudflare tunnel proxy and the apps Gateway reach
# it from the pod network, so its trusted proxies are the pod CIDR. HA 2026.8
# keeps those in .storage/http, not configuration.yaml.
{ config, lib, ... }:
let
  name = "home-assistant";
  namespace = "home-assistant";
  labels."app.kubernetes.io/name" = name;
  port = 8123;
  hostname = "ha.kidibox.net";
  # The image's nobody user; the imported /config is chowned to it.
  uid = 65534;
  # renovate: datasource=docker depName=ghcr.io/home-operations/home-assistant
  tag = "2026.11.1@sha256:c129b1e4190273254d93d413fe2a083233c9202d84cb08f84dddb01861df432e";
  # Where its integrations' devices live (ESPHome, Overkiz, HEOS, the charger's
  # Modbus, TVs, cameras, the vacuums' local APIs).
  deviceNetworkNames = [
    "IotLocal"
    "IotInternet"
    "Trusted"
    "Guest"
  ];
  deviceNetworks =
    deviceNetworkNames
    # The environment's resolved networks carry the computed cidr.
    |> map (n: config.den.environments.${config.den.networks.${n}.environment}.networks.${n}.cidr);

  servicePort = {
    name = "http";
    inherit port;
    protocol = "TCP";
    # The tunnel proxy only passes WebSocket upgrades to a Service port with
    # a ws appProtocol, so an ExternalBackend can't be used.
    appProtocol = "kubernetes.io/ws";
  };
  backendRefs = [
    {
      group = "";
      kind = "Service";
      inherit name port;
      weight = 1;
    }
  ];
in
{
  # Its egress IPs, one per node: see den.clusters.<name>.egressGateways.
  # Outside the K3s DHCP pool (10.0.40.200-254).
  den.clusters.prd.egressGateways.${name} =
    let
      inherit (config.den.environments.prd.networks.K3s.methods) host;
    in
    {
      k3s-prd-0 = host 20;
      k3s-prd-1 = host 21;
      k3s-prd-2 = host 22;
    };

  # RouterOS access this app needs — see modules/den/quirks/firewall.nix.
  den.aspects.kubernetes.home-assistant.home-assistant.firewall =
    { cluster, ... }:
    [
      {
        inherit (cluster) network;
        forward =
          # Only HA's own egress IPs (its CiliumEgressGatewayPolicies below).
          lib.concatMap (
            n:
            lib.mapAttrsToList (node: address: {
              action = "accept";
              src_address = address;
              out_interface = n;
              comment = "Allow HomeAssistant on K3s (${node}) to reach its devices on ${n}";
            }) cluster.egressGateways.${name}
          ) deviceNetworkNames;
      }
    ];

  den.aspects.kubernetes.home-assistant.home-assistant.k8s-manifests =
    { cluster, ... }:
    {
      applications.cloudflare-tunnel-gateway.resources.ciliumNetworkPolicies.cloudflare-tunnel-home-assistant =
        with cluster.methods.netpol;
        mkPolicy { "app.kubernetes.io/name" = "cloudflare-tunnel-gateway-controller-proxy"; } {
          egress = [
            {
              toEndpoints = [
                {
                  matchLabels = labels // {
                    "k8s:io.kubernetes.pod.namespace" = namespace;
                  };
                }
              ];
              toPorts = tcp [ port ];
            }
          ];
        };

      applications.home-assistant = {
        inherit namespace;
        flux.dependsOn = [
          # The kopiur webhook admits the backup objects.
          "kopiur-config"
          # Its operator registers the CiliumEgressGatewayPolicy CRD.
          "cilium"
        ];

        resources =
          cluster.methods.mkKopiurBackup {
            inherit name uid;
            storage = "5Gi";
            ignore = [
              # Rebuilt by the image's entrypoint on every start.
              "/.venv"
              "/deps"
              "/.cache"
              # HA's own backups; the snapshots are the backup here.
              "/backups"
              "/tts"
              "/home-assistant.log*"
            ];
          }
          // {
            services.${name}.spec = {
              selector = labels;
              ports = [ servicePort ];
            };

            httpRoutes = {
              # The public route, through the Cloudflare tunnel.
              ${name} = {
                metadata.labels."home-ops.dev/public-dns" = "true";
                spec = {
                  parentRefs = [
                    {
                      group = "gateway.networking.k8s.io";
                      kind = "Gateway";
                      name = "cloudflare-tunnel";
                      namespace = "cloudflare-tunnel-system";
                      sectionName = "http";
                    }
                  ];
                  hostnames = [ hostname ];
                  rules = [ { inherit backendRefs; } ];
                };
              };
              # The LAN's own route: the internal external-dns points
              # ${hostname} at the apps Gateway (it skips the public route).
              "${name}-internal".spec = {
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
                rules = [ { inherit backendRefs; } ];
              };
            };

            ciliumNetworkPolicies.${name} =
              with cluster.methods.netpol;
              mkPolicy labels {
                ingress = [
                  (tunnelIngress port)
                  (gatewayIngress port)
                  # Destination unreachable from rb5009 for an offline device:
                  # dropped, the connection hangs until it times out instead.
                  {
                    fromEntities = [ "world" ];
                    icmps = [
                      {
                        fields = [
                          {
                            type = "DestinationUnreachable";
                            family = "IPv4";
                          }
                        ];
                      }
                    ];
                  }
                ];
                egress = [
                  (toPods { "app.kubernetes.io/name" = "mosquitto"; } [ 8883 ])
                  # In-cluster apps by their hostname: Plex at plex.kidibox.net.
                  gatewayEgress
                  # Its devices, on whatever ports their integrations use.
                  { toCIDR = deviceNetworks; }
                  # Cloud integrations on whatever ports they use (dreame's
                  # cloud on 13267, Roborock's MQTT on 8883, ...), PyPI for
                  # custom integrations' requirements, HACS (GitHub). A blocked
                  # one hangs HA's startup, and with it the recorder.
                  { toEntities = [ "world" ]; }
                ];
              };

            # Its device traffic leaves from its own IP on the node it runs on,
            # which the RouterOS rules in this file's firewall quirk admit.
            ciliumEgressGatewayPolicies = lib.mapAttrs' (
              node: address:
              let
                onNode.matchLabels."kubernetes.io/hostname" = node;
              in
              lib.nameValuePair "${name}-${node}" {
                spec = {
                  selectors = [
                    {
                      podSelector.matchLabels = labels // {
                        "io.kubernetes.pod.namespace" = namespace;
                      };
                      nodeSelector = onNode;
                    }
                  ];
                  destinationCIDRs = deviceNetworks;
                  egressGateway = {
                    nodeSelector = onNode;
                    egressIP = address;
                  };
                };
              }
            ) cluster.egressGateways.${name};

            deployments.${name}.spec = {
              strategy.type = "Recreate";
              selector.matchLabels = labels;
              template = {
                metadata = { inherit labels; };
                spec = {
                  automountServiceAccountToken = false;
                  # HA's shutdown stops its integrations, then the recorder
                  # commits and closes the database: 30s cut it short.
                  terminationGracePeriodSeconds = 120;
                  securityContext = {
                    runAsNonRoot = true;
                    runAsUser = uid;
                    runAsGroup = uid;
                    fsGroup = uid;
                    fsGroupChangePolicy = "OnRootMismatch";
                    seccompProfile.type = "RuntimeDefault";
                  };
                  containers.${name} = {
                    image = "ghcr.io/home-operations/home-assistant:${tag}";
                    ports.http.containerPort = port;
                    # The entrypoint first rebuilds /config/.venv with the
                    # custom integrations' requirements.
                    startupProbe = {
                      httpGet = {
                        path = "/manifest.json";
                        port = "http";
                      };
                      periodSeconds = 10;
                      failureThreshold = 60;
                    };
                    livenessProbe.httpGet = {
                      path = "/manifest.json";
                      port = "http";
                    };
                    securityContext = {
                      allowPrivilegeEscalation = false;
                      readOnlyRootFilesystem = true;
                      capabilities.drop = [ "ALL" ];
                    };
                    resources = {
                      requests = {
                        cpu = "100m";
                        memory = "512Mi";
                      };
                      limits.memory = "2Gi";
                    };
                    volumeMounts = {
                      "/config".name = "config";
                      "/tmp".name = "tmp";
                    };
                  };
                  volumes = {
                    config.persistentVolumeClaim.claimName = name;
                    tmp.emptyDir = { };
                  };
                };
              };
            };
          };
      };
    };
}
