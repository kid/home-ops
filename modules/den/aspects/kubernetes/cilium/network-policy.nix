# Types only: the chart ships no CRDs, the operator registers them at runtime.
_:
let
  portsOf = protocols: ports: [
    {
      ports = builtins.concatMap (
        port:
        map (protocol: {
          port = toString port;
          inherit protocol;
        }) protocols
      ) ports;
    }
  ];
  tcp = portsOf [ "TCP" ];
  tcpUdp = portsOf [
    "UDP"
    "TCP"
  ];

  fromNamespace = namespace: labels: ports: {
    fromEndpoints = [
      {
        matchLabels = labels // {
          "k8s:io.kubernetes.pod.namespace" = namespace;
        };
      }
    ];
    toPorts = tcp ports;
  };

  netpol = {
    inherit tcp tcpUdp;

    mkPolicy = labels: rules: {
      spec = {
        endpointSelector.matchLabels = labels;
      }
      // rules;
    };

    # Same namespace only.
    fromPods = labels: ports: {
      fromEndpoints = [ { matchLabels = labels; } ];
      toPorts = tcp ports;
    };
    toPods = labels: ports: {
      toEndpoints = [ { matchLabels = labels; } ];
      toPorts = tcp ports;
    };

    apiserverEgress = {
      toEntities = [ "kube-apiserver" ];
      toPorts = tcp [ 6443 ];
    };
    webhookIngress = port: {
      fromEntities = [ "kube-apiserver" ];
      toPorts = tcp [ port ];
    };
    scrapeIngress = fromNamespace "monitoring" { "app.kubernetes.io/name" = "vmagent"; };
    gatewayIngress =
      port: fromNamespace "envoy-gateway-system" { "app.kubernetes.io/name" = "envoy"; } [ port ];
    tunnelIngress =
      port:
      fromNamespace "cloudflare-tunnel-system" {
        "app.kubernetes.io/name" = "cloudflare-tunnel-gateway-controller-proxy";
      } [ port ];
    fqdnEgress = names: ports: {
      toFQDNs = map (matchName: { inherit matchName; }) names;
      toPorts = tcp ports;
    };
    worldEgress = ports: {
      toEntities = [ "world" ];
      toPorts = tcp ports;
    };
    clusterEgress.toEntities = [ "cluster" ];
  };
in
{
  den.clusters.prd.methods.netpol = netpol;

  den.aspects.kubernetes.cilium-network-policy.k8s-manifests =
    { generators, pkgs, ... }:
    {
      nixidy.applicationImports = [
        (generators.fromCRDModule {
          name = "cilium";
          src = pkgs.fetchFromGitHub {
            owner = "cilium";
            repo = "cilium";
            # renovate: datasource=github-releases depName=cilium/cilium
            rev = "v1.20.2";
            hash = "sha256-F8zFd3jsvgn64WnYgzGQPUIt6b8l4/yUlncTyVLCQCc=";
          };
          crdFiles = [
            "pkg/k8s/apis/cilium.io/client/crds/v2/ciliumnetworkpolicies.yaml"
            "pkg/k8s/apis/cilium.io/client/crds/v2/ciliumclusterwidenetworkpolicies.yaml"
          ];
          kindFilter = [
            "CiliumNetworkPolicy"
            "CiliumClusterwideNetworkPolicy"
          ];
        })
      ];

      applications.cilium.resources.ciliumClusterwideNetworkPolicies = {
        default-deny.spec = {
          description = "Deny all pod traffic not allowed by another policy; allow DNS to CoreDNS.";
          endpointSelector = { };
          enableDefaultDeny = {
            ingress = true;
            egress = true;
          };
          # A section needs a rule for its default deny to apply.
          ingress = [ { fromEntities = [ "host" ]; } ];
          egress = [
            {
              toEndpoints = [
                {
                  matchLabels = {
                    "k8s:io.kubernetes.pod.namespace" = "kube-system";
                    k8s-app = "coredns";
                  };
                }
              ];
              toPorts = [
                {
                  inherit (builtins.head (tcpUdp [ 53 ])) ports;
                  rules.dns = [ { matchPattern = "*"; } ];
                }
              ];
            }
          ];
        };

        cilium-health-checks.spec = {
          endpointSelector.matchLabels."reserved:health" = "";
          ingress = [ { fromEntities = [ "remote-node" ]; } ];
          egress = [ { toEntities = [ "remote-node" ]; } ];
        };
      };
    };
}
