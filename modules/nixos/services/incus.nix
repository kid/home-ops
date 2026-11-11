_: {
  den.aspects.incus.datasets."zroot/incus".properties.mountpoint = "none";

  den.aspects.incus.nixos =
    { pkgs, ... }:
    {
      virtualisation.incus.package = pkgs.incus;
      virtualisation.incus.enable = true;
      networking.nftables.enable = true;
      networking.firewall.allowedTCPPorts = [ 8443 ];

      # Incus creates and owns everything under its pool's dataset; without
      # this, disko-zfs lists each of them as a dataset to destroy.
      disko.zfs.settings.ignoredDatasets = [ "zroot/incus/*" ];

      boot.kernel.sysctl = {
        "net.bridge.bridge-nf-call-iptables" = 0;
        "net.bridge.bridge-nf-call-ip6tables" = 0;
        "net.bridge.bridge-nf-call-arptables" = 0;
        # VM migrations from node1 (10G) to node0 (2.5G) overflow rb5009's
        # switch buffers (sfp-sfpplus1 rx-overflow) and CUBIC collapses to
        # ~50MiB/s on the losses; BBR paces to the bottleneck instead.
        "net.core.default_qdisc" = "fq";
        "net.ipv4.tcp_congestion_control" = "bbr";
      };
      boot.kernelModules = [ "tcp_bbr" ];

      virtualisation.incus.preseed = {
        config."core.https_address" = ":8443";

        storage_pools = [
          {
            name = "default";
            driver = "zfs";
            config.source = "zroot/incus";
          }
        ];
      };
    };
}
