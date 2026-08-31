# Split out of k3s-server (modules/den/aspects/services/k3s/k3s.nix): k3s
# flags and firewall settings that only make sense when Cilium is the
# host's CNI. Only hosts that actually run Cilium should include this.
_: {
  den.aspects.k3s-cilium.nixos =
    { lib, pkgs, ... }:
    {
      services.k3s.extraFlags = [
        "--flannel-backend=none"
        "--disable-network-policy"
        "--disable-kube-proxy"
        # traefik -> Cilium Gateway API, servicelb -> Cilium BGP LB
        "--disable=traefik"
        "--disable=servicelb"
      ];

      # Cilium's own host firewall (modules/den/aspects/kubernetes/cilium/host-firewall.nix) replaces it.
      networking.firewall.enable = lib.mkForce false;
      networking.nftables.enable = true;

      environment.systemPackages = with pkgs; [ bpftools ];
    };
}
