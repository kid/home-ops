# Split out of k3s-server (modules/den/aspects/services/k3s/k3s.nix): k3s
# flags and firewall settings that only make sense when Cilium is the
# host's CNI. Only hosts that actually run Cilium should include this.
_: {
  den.aspects.k3s-cilium.nixos = _: {
    services.k3s.extraFlags = [
      "--flannel-backend=none"
      "--disable-network-policy"
      "--disable-kube-proxy"
      # traefik -> Cilium Gateway API, servicelb -> Cilium BGP LB
      "--disable=traefik"
      "--disable=servicelb"
    ];

    networking.firewall.trustedInterfaces = [
      "k3s"
      "cilium_net"
      "cilium_host"
      "cilium_vxlan"
      "lxc*"
    ];
    networking.nftables.enable = true;
  };
}
