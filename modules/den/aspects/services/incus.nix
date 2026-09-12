_: {
  den.aspects.incus.datasets."zroot/incus".properties.mountpoint = "none";

  den.aspects.incus.nixos = _: {
    virtualisation.incus.enable = true;
    networking.nftables.enable = true;
    networking.firewall.allowedTCPPorts = [ 8443 ];

    virtualisation.incus.preseed.storage_pools = [
      {
        name = "default";
        driver = "zfs";
        config.source = "zroot/incus";
      }
    ];
  };
}
