# srvos server profile and housekeeping for the headless fleet hosts.
{ inputs, ... }:
{
  den.aspects.server.nixos =
    { lib, ... }:
    {
      imports = [ inputs.srvos.nixosModules.server ];

      # The hosts are ZFS-only, and LVM would scan their zvols and activate
      # volume groups guests created on them.
      services.lvm.enable = lib.mkDefault false;

      # Drops system generations older than two weeks, then everything no
      # longer rooted, including the in-cluster CI runner's build outputs
      # (modules/kubernetes/actions-runner-controller): the next CI run after
      # it rebuilds what changed since the host's own system.
      nix.gc = {
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 14d";
      };
    };
}
