# VM test of den.aspects.disk.zfs and den.aspects.impermanence. A fixture
# host includes both, like node0 and node1; disko's installTest formats its
# layout (the real postCreateHooks take @empty), installs the host's own
# den-resolved NixOS configuration, then boots it from that disk twice.
{
  pkgs,
  inputs,
  modulesTree,
}:
let
  testScript = ''
    def boot():
        machine.wait_for_unit("multi-user.target")

    boot()

    with subtest("the initrd rolled the root dataset back"):
        machine.succeed("findmnt -no SOURCE / | grep -qx zroot/local/root")
        machine.succeed("zfs list -H -t snapshot zroot/local/root@empty")
        machine.succeed("journalctl -b -u rollback-root.service | grep -q 'Finished'")

    machine_id = machine.succeed("cat /etc/machine-id")
    host_key = machine.succeed("cat /etc/ssh/ssh_host_ed25519_key.pub")
    machine.succeed(
        "touch /etc/ephemeral /root/ephemeral /var/lib/kept/canary /var/log/canary /home/canary"
    )
    machine.succeed("sync")
    machine.shutdown()
    machine.start()
    boot()

    with subtest("the root is empty again"):
        machine.fail("test -e /etc/ephemeral")
        machine.fail("test -e /root/ephemeral")

    with subtest("persist, cache and /home survive"):
        machine.succeed("findmnt -no SOURCE /var/lib/kept | grep -q zroot/local/persist")
        machine.succeed("test -e /var/lib/kept/canary")
        machine.succeed("test -e /var/log/canary")
        machine.succeed("test -e /home/canary")
        assert machine.succeed("cat /etc/machine-id") == machine_id
        assert machine.succeed("cat /etc/ssh/ssh_host_ed25519_key.pub") == host_key
  '';

  fixture =
    { den, ... }:
    {
      den.hosts.x86_64-linux.imp = {
        # Only a test node, not a nixosConfigurations output.
        intoAttr = [ ];
        environment = "prd";
        # installTest swaps in the test VM's own disks.
        settings.disk.zfs.device = "/dev/disk/by-id/fixture";
      };

      den.aspects.imp = {
        includes = [
          den.aspects.base
          den.aspects.disk.zfs
          den.aspects.impermanence
        ];

        # Collected into environment.persistence like any aspect's.
        persist.directories = [ "/var/lib/kept" ];

        nixos = {
          networking.hostName = "imp";
          networking.hostId = "8425e349";
          disko.tests.extraChecks = testScript;
          # Its pre-switch diff queries the store database, which the
          # installer leaves empty under /mnt.
          srvos.update-diff.enable = false;
        };
      };
    };

  host =
    (inputs.flake-parts.lib.evalFlakeModule { inherit inputs; } {
      imports = [
        modulesTree
        fixture
      ];
    }).config.den.hosts.x86_64-linux.imp;

  nixos = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      host.mainModule
      { nixpkgs.pkgs = pkgs; }
    ];
  };
in
{
  impermanence-zfs-rollback = nixos.config.system.build.installTest;
}
