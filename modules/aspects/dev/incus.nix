# Incus containers and VMs on a btrfs storage pool, administered by the privileged user.
_: {
  den.aspects.dev.incus = {
    persist.directories = [ "/var/lib/incus" ];

    nixos =
      { lib, pkgs, ... }:
      {
        users.privilegedGroups = [ "incus-admin" ];

        networking.nftables.enable = lib.mkDefault true;

        environment.systemPackages = with pkgs; [
          incus
          ovn
        ];

        virtualisation.incus = {
          enable = true;
          package = pkgs.incus;
          ui.enable = true;
          preseed = {
            config."core.https_address" = "[::]:8443";
            networks = [ ];
            profiles = [
              {
                name = "default";
                devices.root = {
                  path = "/";
                  pool = "default";
                  type = "disk";
                };
              }
            ];
            storage_pools = [
              {
                name = "default";
                driver = "btrfs";
                config.source = "/var/lib/incus/storage-pools/default";
              }
            ];
          };
        };
      };
  };
}
