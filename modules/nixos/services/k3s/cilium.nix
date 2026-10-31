# Split out of k3s-server (modules/nixos/services/k3s/k3s.nix): k3s
# flags and firewall settings that only make sense when Cilium is the
# host's CNI. Only hosts that actually run Cilium should include this.
_: {
  den.aspects.k3s-cilium.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      services.k3s.extraFlags =
        if config.services.k3s.role == "server" then
          [
            "--flannel-backend=none"
            "--disable-network-policy"
            "--disable-kube-proxy"
            # traefik -> Cilium Gateway API, servicelb -> Cilium BGP LB
            "--disable=traefik"
            "--disable=servicelb"
          ]
        else
          # Cilium reaches the API at 127.0.0.1:6443 on every node
          # (kubernetes/cilium's k8sServiceHost). An agent has no apiserver
          # there, so move its own apiserver load balancer (default 6444) to it.
          [ "--lb-server-port=6443" ];

      # Cilium's own host firewall (modules/kubernetes/cilium/host-firewall.nix) replaces it.
      networking.firewall.enable = lib.mkForce false;
      networking.nftables.enable = true;

      environment.systemPackages = with pkgs; [ bpftools ];
    };
}
