# Throwaway QEMU host, not real hardware. Smoke-tests the k3s / system
# containerd / zfs snapshotter wiring end-to-end:
# `nix build .#nixosConfigurations.test-vm.config.system.build.vmWithDisko`
{ den, ... }:
{
  den.hosts.x86_64-linux.test-vm = {
    environment = "prd";
    settings = {
      k3s.clusterName = "prd";
      # Irrelevant under disko's testMode: vmWithDisko substitutes its own
      # qcow2 images regardless of the configured device.
      disk.zfs.device = "/dev/vda";
    };
  };

  den.aspects.test-vm.nixos =
    { lib, ... }:
    {
      boot.loader.efi.canTouchEfiVariables = true;

      networking.hostId = "deadbeef";
      networking.hostName = "test-vm";
      networking.useDHCP = lib.mkDefault true;

      # Throwaway box, console-only: fixed known password for smoke-testing.
      users.users.root.initialPassword = "root";
    };

  den.aspects.test-vm.includes = [
    den.aspects.base
    den.aspects.disk.zfs
    den.aspects.impermanence
    den.aspects.k3s.server
  ];
}
