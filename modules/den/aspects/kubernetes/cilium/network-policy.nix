# Types only: the chart ships no CRDs, the operator registers them at runtime.
_:
let
  tcp = ports: [
    {
      ports = map (port: {
        port = toString port;
        protocol = "TCP";
      }) ports;
    }
  ];

  fromPods = namespace: labels: ports: {
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
    apiserverEgress = {
      toEntities = [ "kube-apiserver" ];
      toPorts = tcp [ 6443 ];
    };
    webhookIngress = port: {
      fromEntities = [ "kube-apiserver" ];
      toPorts = tcp [ port ];
    };
    scrapeIngress = fromPods "monitoring" { "app.kubernetes.io/name" = "vmagent"; };
    gatewayIngress =
      port: fromPods "envoy-gateway-system" { "app.kubernetes.io/name" = "envoy"; } [ port ];
    tunnelIngress =
      port:
      fromPods "cloudflare-tunnel-system" {
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
    };
}
