# Throwaway QEMU host, not real hardware. Smoke-tests the k3s / system
# containerd / zfs snapshotter wiring end-to-end:
# `nix build .#nixosConfigurations.test-vm.config.system.build.vmWithDisko`
{ den, ... }:
{
  den.hosts.x86_64-linux.test-vm = {
    k3s.clusterName = "prd";
    # Irrelevant under disko's testMode: vmWithDisko substitutes its own
    # qcow2 images regardless of the configured device.
    settings.disko.zfs-disk-single.settings.device_id = "/dev/vda";
  };

  den.aspects.test-vm.nixos =
    { lib, ... }:
    {
      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;

      networking.hostId = lib.mkDefault "deadbeef";
      networking.hostName = "test-vm";
      networking.useDHCP = lib.mkDefault true;

      users.mutableUsers = false;
      # Throwaway box, console-only: fixed known password for smoke-testing.
      users.users.root.initialPassword = "root";
      security.sudo.enable = true;
      security.sudo.wheelNeedsPassword = false;

      services.openssh.enable = true;

      system.stateVersion = "26.05";
    };

  den.aspects.test-vm.includes = [
    den.aspects.disko.zfs-disk-single
    den.aspects.impermanence
    den.aspects.impermanence.tmpfs
    den.aspects.k3s-server
  ];
}
