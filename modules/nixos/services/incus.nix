_: {
  den.aspects.incus.datasets."zroot/incus".properties.mountpoint = "none";

  den.aspects.incus.nixos = _: {
    virtualisation.incus.enable = true;
    networking.nftables.enable = true;
    networking.firewall.allowedTCPPorts = [ 8443 ];

    boot.kernel.sysctl = {
      "net.bridge.bridge-nf-call-iptables" = 0;
      "net.bridge.bridge-nf-call-ip6tables" = 0;
      "net.bridge.bridge-nf-call-arptables" = 0;
    };

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
