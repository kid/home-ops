# Home Assistant. Until the cutover (inCluster = false) it still runs on the
# HAOS VM on the Servers VLAN: the Service has no selector and an EndpointSlice
# lists the VM, and the Deployment is scaled to zero. At the cutover its
# /config is imported once into the kopiur-backed volume and inCluster flips
# the Service, the tunnel's egress and the Deployment over to the pod.
#
# HA has its own login. The Cloudflare tunnel proxy and the apps Gateway reach
# it from the pod network, so its configuration.yaml needs
# http.use_x_forwarded_for with the pod CIDR in http.trusted_proxies.
{ config, lib, ... }:
let
  inCluster = false;

  name = "home-assistant";
  namespace = "home-assistant";
  labels."app.kubernetes.io/name" = name;
  port = 8123;
  hostname = "ha.kidibox.net";
  vmAddress = config.den.devices.homeassistant.address;
  # The image's nobody user; the imported /config is chowned to it.
  uid = 65534;
  # Same version as the VM, so the imported database isn't migrated at the
  # cutover.
  # renovate: datasource=docker depName=ghcr.io/home-operations/home-assistant
  tag = "2026.8.2@sha256:84f5b1b26e1597a3d5a19a7b6e2ed085ec8e3fffcbe46049acf62f9e25ea400e";
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
  # RouterOS access this app needs — see modules/den/quirks/firewall.nix.
  den.aspects.kubernetes.home-assistant.home-assistant.firewall =
    { cluster, ... }:
    [
      {
        inherit (cluster) network;
        forward =
          lib.optional (!inCluster) {
            action = "accept";
            dst_address = vmAddress;
            dst_port = port;
            protocol = "tcp";
            comment = "Allow access to HomeAssistant from K3s for the Cloudflare tunnel";
          }
          # Only HA's own egress IPs (its CiliumEgressGatewayPolicies below).
          ++ lib.concatMap (
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
            (
              if inCluster then
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
              else
                {
                  toCIDR = [ "${vmAddress}/32" ];
                  toPorts = tcp [ port ];
                }
            )
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
              ports = [ servicePort ];
            }
            // lib.optionalAttrs inCluster { selector = labels; };

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
            }
            // lib.optionalAttrs inCluster {
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
                ];
                egress = [
                  (toPods { "app.kubernetes.io/name" = "mosquitto"; } [ 8883 ])
                  # In-cluster apps by their hostname: Plex at plex.kidibox.net.
                  gatewayEgress
                  # Its devices, on whatever ports their integrations use.
                  { toCIDR = deviceNetworks; }
                  # Cloud integrations, PyPI for custom integrations'
                  # requirements, HACS (GitHub).
                  (worldEgress [
                    80
                    443
                  ])
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
              # 1 only once the VM's /config is imported and the VM is stopped.
              replicas = if inCluster then 1 else 0;
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
          }
          // lib.optionalAttrs (!inCluster) {
            # The Service has no selector: list the VM by hand.
            endpointSlices.${name} = {
              metadata.labels = {
                "kubernetes.io/service-name" = name;
                "endpointslice.kubernetes.io/managed-by" = "home-ops";
              };
              addressType = "IPv4";
              ports = [ servicePort ];
              endpoints = [
                {
                  addresses = [ vmAddress ];
                  conditions.ready = true;
                }
              ];
            };
          };
      };
    };
}
