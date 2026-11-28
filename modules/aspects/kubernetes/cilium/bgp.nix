# Cilium BGP Control Plane resources — LoadBalancer IP pool + direct BGP
# peering with rb5009 (den.clusters.<name>.bgp, see modules/den/schema/
# clusters.nix), so LoadBalancer Services get real, routable addresses
# instead of NodePort-only reachability. Mirrors the legacy dev cluster's
# kubernetes/apps/kube-system/cilium/resources/networking.yaml (Flux
# ${NETWORK_*} env-var substituted) — same four resources, but values come
# straight from den.clusters.<name>.bgp/.networks.loadBalancer since prd
# renders through nixidy, not Flux postBuild substitution. Requires
# modules/aspects/kubernetes/cilium/default.nix's bgpControlPlane.enabled Helm
# value. The RouterOS side of the same peering is this aspect's `tofu`
# content, in the cluster's tofu stack.
{ config, lib, ... }:
let
  providerName = "routeros-ebogdum";

  # RouterOS echoes duration values back in its own canonical form (e.g.
  # 90 seconds reads back as "1m30s", not "90s") — the ebogdum/routeros
  # provider's plugin-framework-based consistency check treats a
  # non-canonical value we send as a post-apply drift and errors ("provider
  # produced inconsistent result"). Send the canonical form ourselves.
  formatRouterosDuration =
    totalSeconds:
    let
      w = totalSeconds / 604800;
      afterW = totalSeconds - (w * 604800);
      d = afterW / 86400;
      afterD = afterW - (d * 86400);
      h = afterD / 3600;
      afterH = afterD - (h * 3600);
      m = afterH / 60;
      s = afterH - (m * 60);
      segmentsWithoutSeconds =
        lib.optional (w > 0) "${toString w}w"
        ++ lib.optional (d > 0) "${toString d}d"
        ++ lib.optional (h > 0) "${toString h}h"
        ++ lib.optional (m > 0) "${toString m}m";
    in
    lib.concatStrings (
      segmentsWithoutSeconds ++ lib.optional (s > 0 || segmentsWithoutSeconds == [ ]) "${toString s}s"
    );
in
{
  # The Service annotation that pins a LoadBalancer to its
  # den.clusters.<name>.networks.loadBalancer.assignments.<name> address
  # through Cilium's LB-IPAM. Empty without an assignment: the Service gets
  # the next free address in the pool.
  den.clusterMethods.lbIpamAnnotations =
    cluster: name:
    let
      assignments = cluster.networks.loadBalancer.assignments or { };
    in
    lib.optionalAttrs (assignments ? ${name}) {
      "lbipam.cilium.io/ips" = assignments.${name};
    };

  # The router side of each peering, in the cluster's tofu stack: on every
  # bgp.peers router, a BGP instance and template named after the cluster
  # and one connection per node. Untyped, through the ebogdum/routeros
  # provider (see the tofu battery's _providers.nix): terraform-routeros's
  # BGP creates are rejected by RouterOS (its #959), and both providers'
  # resource types start with routeros_. One aliased provider per router,
  # with that router's login (its routerosInputs.base, modules/fleet/routeros/).
  den.aspects.kubernetes.cilium-bgp.tofu =
    {
      cluster,
      k3s-nodes,
      ...
    }:
    let
      # Drop hosts with no real address (e.g. test-vm, a throwaway QEMU
      # smoke-test host — see k3s.nix's k3s-nodes quirk).
      nodes = k3s-nodes |> lib.filter (n: n.address != null);

      idFor = peer: "cilium_bgp_${peer.name}";
      providerFor = peer: "${providerName}.${peer.name}";

      resourcesFor =
        peer:
        let
          id = idFor peer;
          provider = providerFor peer;
        in
        {
          routeros_routing_bgp_instance.${id} = {
            inherit provider;
            name = "${cluster.name}-bgp";
            as = peer.asn;
            router_id = peer.ip;
            vrf = "main";
          };
          routeros_routing_bgp_template.${id} = {
            inherit provider;
            name = "${cluster.name}-peers";
            as = peer.asn;
            routing_table = "main";
            hold_time = formatRouterosDuration cluster.bgp.holdTimeSeconds;
            keepalive_time = formatRouterosDuration cluster.bgp.keepAliveTimeSeconds;
          };
          routeros_routing_bgp_connection =
            nodes
            |> map (
              node:
              lib.nameValuePair "${id}_${node.hostname}" {
                inherit provider;
                name = "${cluster.name}-${node.hostname}";
                as = peer.asn;
                instance = "\${routeros_routing_bgp_instance.${id}.name}";
                templates = "\${routeros_routing_bgp_template.${id}.name}";
                connect = "true";
                listen = "true";
                afi = "ip";
                routing_table = "main";
                local_role = "ebgp";
                remote_address = node.address;
                remote_as = cluster.bgp.localAsn;
              }
            )
            |> lib.listToAttrs;
        };

      loginFor = peer: config.den.aspects.${peer.name}.routerosInputs.base.inputs;
    in
    lib.optionalAttrs (cluster.bgp.peers != [ ]) {
      terraform.required_providers.${providerName} = {
        source = "registry.terraform.io/ebogdum/routeros";
        version = (import ../../../den/batteries/tofu/_providers.nix).routeros-ebogdum.version;
      };

      data.onepassword_item =
        cluster.bgp.peers
        |> map (
          peer:
          lib.nameValuePair (idFor peer) {
            vault = (loginFor peer).op_vault;
            title = (loginFor peer).op_item_routeros;
          }
        )
        |> lib.listToAttrs;

      untyped.provider.${providerName} =
        cluster.bgp.peers
        |> map (
          peer:
          lib.nameValuePair peer.name {
            host = "\${data.onepassword_item.${idFor peer}.url}";
            username = "\${data.onepassword_item.${idFor peer}.username}";
            password = "\${data.onepassword_item.${idFor peer}.password}";
            insecure = true;
          }
        )
        |> lib.listToAttrs;

      untyped.resource = cluster.bgp.peers |> map resourcesFor |> lib.foldl' lib.recursiveUpdate { };
    };

  # RouterOS access this BGP peering needs — see modules/den/quirks/firewall.nix.
  # Clusters sharing a network emit the same rule; modules/aspects/routeros/firewall.nix
  # keeps one.
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
      peersJson =
        peers
        |> map (p: {
          inherit (p) name;
          peerASN = p.asn;
          peerAddress = p.ip;
          peerConfigRef.name = "l3-bgp-peer-config";
        })
        |> builtins.toJSON;
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
