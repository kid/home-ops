# Cilium BGP Control Plane resources — LoadBalancer IP pool + direct BGP
# peering with rb5009 (den.clusters.<name>.bgp, see modules/den/schema/
# clusters.nix), so LoadBalancer Services get real, routable addresses
# instead of NodePort-only reachability. Mirrors the legacy dev cluster's
# kubernetes/apps/kube-system/cilium/resources/networking.yaml (Flux
# ${NETWORK_*} env-var substituted) — same four resources, but values come
# straight from den.clusters.<name>.bgp/.networks.loadBalancer since prd
# renders through nixidy, not Flux postBuild substitution. Requires
# modules/den/aspects/kubernetes/cilium/default.nix's bgpControlPlane.enabled Helm
# value and modules/den/aspects/routeros/bgp.nix (the RouterOS side of this
# same peering) for BGP sessions to actually come up.
_: {
  # Router-access rule this BGP peering needs (k3s nodes reaching rb5009's
  # BGP port) — a `firewall` quirk fragment (den.quirks.firewall), collected
  # onto rb5009 by modules/den/policies/pipes.nix's
  # routeros-device-collect-firewall and merged by modules/den/aspects/
  # routeros/firewall.nix into the K3s network's rule lists.
  den.aspects.kubernetes.cilium-bgp.firewall = { cluster, ... }: [
    {
      inherit (cluster) network;
      input = [
        {
          action = "accept";
          dst_address = (builtins.head cluster.bgp.peers).ip;
          dst_port = 179;
          protocol = "tcp";
          comment = "Allow BGP from k3s nodes to rb5009 for Cilium";
        }
      ];
    }
  ];

  den.aspects.kubernetes.cilium-bgp.k8s-manifests =
    { cluster, ... }:
    let
      inherit (cluster.bgp)
        localAsn
        peers
        holdTimeSeconds
        keepAliveTimeSeconds
        ;
      lbCidr = cluster.networks.loadBalancer.cidr;

      # Encoded as JSON (valid inline YAML) rather than hand-templated
      # multi-line YAML, so this isn't hardcoded to one peer.
      peersJson = builtins.toJSON (
        map (p: {
          inherit (p) name;
          peerASN = p.asn;
          peerAddress = p.ip;
          peerConfigRef.name = "l3-bgp-peer-config";
        }) peers
      );
    in
    {
      applications.cilium.yamls = [
        ''
          apiVersion: cilium.io/v2
          kind: CiliumLoadBalancerIPPool
          metadata:
            name: pool
          spec:
            allowFirstLastIPs: "No"
            blocks:
              - cidr: "${lbCidr}"
        ''
        ''
          apiVersion: cilium.io/v2
          kind: CiliumBGPAdvertisement
          metadata:
            name: l3-bgp-advertisement
            labels:
              advertise: bgp
          spec:
            advertisements:
              - advertisementType: PodCIDR
              - advertisementType: Service
                service:
                  addresses:
                    - LoadBalancerIP
                selector:
                  matchExpressions:
                    - key: fakeSelector
                      operator: NotIn
                      values:
                        - will-match-and-announce-all-services
        ''
        ''
          apiVersion: cilium.io/v2
          kind: CiliumBGPPeerConfig
          metadata:
            name: l3-bgp-peer-config
          spec:
            timers:
              holdTimeSeconds: ${toString holdTimeSeconds}
              keepAliveTimeSeconds: ${toString keepAliveTimeSeconds}
            families:
              - afi: ipv4
                safi: unicast
                advertisements:
                  matchLabels:
                    advertise: bgp
        ''
        ''
          apiVersion: cilium.io/v2
          kind: CiliumBGPClusterConfig
          metadata:
            name: l3-bgp-cluster-config
          spec:
            nodeSelector:
              matchLabels:
                kubernetes.io/os: linux
            bgpInstances:
              - name: cilium
                localASN: ${toString localAsn}
                peers: ${peersJson}
        ''
      ];
    };
}
