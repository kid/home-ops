# Host-side setup for a k3s node running miroir with an lvmthin pool
# (modules/den/aspects/kubernetes/miroir/default.nix's MiroirNode).
{ lib, ... }:
{
  den.aspects.k3s-miroir-node = {
    settings.device = lib.mkOption { type = lib.types.str; };

    nixos = {
      boot.kernelModules = [ "dm_thin_pool" ];

      # miroir-agent bind-mounts the host's /lib/modules for its own
      # modprobe — NixOS leaves that path empty, so without this it fails
      # with "Module dm-thin-pool not found in directory /lib/modules/...".
      systemd.tmpfiles.rules = [
        "L+ /lib/modules - - - - /run/current-system/kernel-modules/lib/modules"
      ];
    };
  };
}
