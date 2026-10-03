# Cilium CNI, configured for kube-proxy replacement + native routing to
# match modules/den/aspects/services/k3s/k3s.nix's k3s flags
# (--flannel-backend=none --disable-network-policy --disable-kube-proxy).
_: {
  # cilium-agent health (9879) and Hubble gRPC (4244) bind on the host itself.
  den.aspects.kubernetes.cilium.firewall-ports = _: [
    {
      port = 9879;
      protocol = "TCP";
      description = "cilium-agent health";
      from = [
        "cluster"
        "remote-node"
      ];
    }
    {
      port = 4244;
      protocol = "TCP";
      description = "Hubble gRPC";
      from = [
        "cluster"
        "remote-node"
      ];
    }
  ];

  den.aspects.kubernetes.cilium.k8s-manifests =
    { charts, cluster, ... }:
    {
      applications.cilium = {
        namespace = "kube-system";
        syncPolicy.syncOptions.serverSideApply = true;

        resources.httpRoutes.hubble-ui.spec = {
          parentRefs = [
            {
              group = "gateway.networking.k8s.io";
              kind = "Gateway";
              name = "apps";
              namespace = "envoy-gateway-system";
              sectionName = "https";
            }
          ];
          hostnames = [ (cluster.methods.mkAppHostname "hubble") ];
          rules = [
            {
              backendRefs = [
                {
                  name = "hubble-ui";
                  port = 80;
                }
              ];
            }
          ];
        };

        # Hubble UI has no login of its own.
        resources.securityPolicies =
          (cluster.methods.mkForwardAuth {
            name = "hubble-ui";
            httpRouteName = "hubble-ui";
          }).securityPolicies;

        resources.ciliumNetworkPolicies = with cluster.methods.netpol; {
          hubble-relay = mkPolicy { k8s-app = "hubble-relay"; } {
            ingress = [ (fromPods { k8s-app = "hubble-ui"; } [ 4245 ]) ];
            egress = [
              {
                toEntities = [
                  "host"
                  "remote-node"
                ];
                toPorts = tcp [ 4244 ];
              }
            ];
          };
          hubble-ui = mkPolicy { k8s-app = "hubble-ui"; } {
            ingress = [ (gatewayIngress 8081) ];
            egress = [
              apiserverEgress
              (toPods { k8s-app = "hubble-relay"; } [ 4245 ])
            ];
          };
        };

        helm.releases.cilium = {
          chart = charts.cilium.cilium;
          values = {
            kubeProxyReplacement = true;
            k8sServiceHost = "127.0.0.1";
            k8sServicePort = 6443;

            routingMode = "native";
            autoDirectNodeRoutes = true;
            ipv4NativeRoutingCIDR = cluster.networks.pods.cidr;

            ipam = {
              mode = "cluster-pool";
              operator.clusterPoolIPv4PodCIDRList = [ cluster.networks.pods.cidr ];
            };

            bpf.masquerade = true;

            hostFirewall.enabled = true;

            # Temporary: also stops enforcing node-host-firewall.
            policyAuditMode = true;
            rollOutCiliumPods = true;

            bgpControlPlane.enabled = true;

            # Gateway API is served by Envoy Gateway instead (see
            # envoy-gateway/default.nix), not Cilium's own controller.
            # envoy.enabled powers Cilium's embedded Envoy proxy, used only
            # for Ingress, Gateway API, L7 network policies, and L7
            # protocol visibility — none of which this cluster uses now.
            envoy.enabled = false;

            resources = {
              requests = {
                cpu = "50m";
                memory = "512Mi";
              };
              limits.memory = "1Gi";
            };
            initResources.requests = {
              cpu = "10m";
              memory = "32Mi";
            };

            operator = {
              replicas = 1;
              prometheus.serviceMonitor.enabled = true;
              resources = {
                requests = {
                  cpu = "10m";
                  memory = "128Mi";
                };
                limits.memory = "256Mi";
              };
            };

            prometheus = {
              enabled = true;
              serviceMonitor = {
                enabled = true;
                # nixidy renders manifests offline (no live API server to
                # check against) — this chart's own validate.yaml otherwise
                # hard-fails the render demanding this exact escape hatch.
                trustCRDsExist = true;
              };
            };

            hubble = {
              relay = {
                enabled = true;
                resources = {
                  requests = {
                    cpu = "10m";
                    memory = "32Mi";
                  };
                  limits.memory = "128Mi";
                };
              };
              ui = {
                enabled = true;
                backend.resources = {
                  requests = {
                    cpu = "10m";
                    memory = "32Mi";
                  };
                  limits.memory = "128Mi";
                };
                frontend.resources = {
                  requests = {
                    cpu = "10m";
                    memory = "32Mi";
                  };
                  limits.memory = "64Mi";
                };
              };

              tls.auto = {
                method = "certmanager";
                certManagerIssuerRef = {
                  group = "cert-manager.io";
                  kind = "ClusterIssuer";
                  name = "hubble-ca-issuer";
                };
              };

              # The chart's own documented example set (values.yaml comment
              # next to hubble.metrics.enabled).
              metrics = {
                enabled = [
                  "dns:query;ignoreAAAA"
                  "drop"
                  "tcp"
                  "flow"
                  "icmp"
                  "http"
                  "policy:sourceContext=app|workload-name|pod|reserved-identity;destinationContext=app|workload-name|pod|dns|reserved-identity;labelsContext=source_namespace,destination_namespace"
                ];
                serviceMonitor.enabled = true;
              };
            };
          };
        };
      };
    };
}
