# VM tests of den.aspects.impermanence on both disk layouts: den.aspects.disk.zfs
# (fixture host imp, like k3s-prd-0 and node1) and den.aspects.disk.btrfs
# (fixture host impb, nested under @/ like vulkan). disko's installTest formats
# each layout (for ZFS, the real postCreateHooks take @empty), installs the
# host's own den-resolved NixOS configuration, then boots it from that disk
# twice.
{
  pkgs,
  inputs,
  modulesTree,
}:
let
  inherit (pkgs) lib;

  # Python statements of a `with subtest` body, each line indented under it.
  indent =
    s:
    s
    |> lib.removeSuffix "\n"
    |> lib.splitString "\n"
    |> lib.concatMapStrings (l: "    ${l}\n");

  testScript =
    { rootChecks, persistSource }:
    ''
      def boot():
          machine.wait_for_unit("multi-user.target")

      boot()

      with subtest("the initrd rolled the root back"):
      ${indent rootChecks}

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
          machine.succeed("findmnt -no SOURCE /var/lib/kept | grep -qF '${persistSource}'")
          machine.succeed("test -e /var/lib/kept/canary")
          machine.succeed("test -e /var/log/canary")
          machine.succeed("test -e /home/canary")
          assert machine.succeed("cat /etc/machine-id") == machine_id
          assert machine.succeed("cat /etc/ssh/ssh_host_ed25519_key.pub") == host_key
    '';

  zfsScript = testScript {
    rootChecks = ''
      machine.succeed("findmnt -no SOURCE / | grep -qx zroot/local/root")
      machine.succeed("zfs list -H -t snapshot zroot/local/root@empty")
      machine.succeed("journalctl -b -u rollback-root.service | grep -q 'Finished'")
    '';
    persistSource = "zroot/local/persist";
  };

  btrfsScript = testScript {
    rootChecks = ''
      machine.succeed("findmnt -no SOURCE / | grep -qF '[/@/root]'")
      machine.succeed("journalctl -b -u rollback-root.service | grep -q 'Finished'")
    '';
    persistSource = "[/@/persist]";
  };

  fixture =
    { den, ... }:
    {
      den.hosts.x86_64-linux = {
        imp = {
          # Only a test node, not a nixosConfigurations output.
          intoAttr = [ ];
          environment = "prd";
          # installTest swaps in the test VM's own disks.
          settings.disk.zfs.device = "/dev/disk/by-id/fixture";
        };

        impb = {
          intoAttr = [ ];
          environment = "prd";
          settings.disk.btrfs = {
            device = "/dev/disk/by-id/fixture";
            subvolumePrefix = "@/";
          };
        };
      };

      den.aspects.imp = {
        includes = [
          den.aspects.profiles.server
          den.aspects.disk.zfs
          den.aspects.impermanence
        ];

        # Collected into environment.persistence like any aspect's.
        persist.directories = [ "/var/lib/kept" ];

        nixos = {
          networking.hostName = "imp";
          networking.hostId = "8425e349";
          disko.tests.extraChecks = zfsScript;
          # Its pre-switch diff queries the store database, which the
          # installer leaves empty under /mnt.
          srvos.update-diff.enable = false;
        };
      };

      den.aspects.impb = {
        includes = [
          den.aspects.profiles.server
          den.aspects.disk.btrfs
          den.aspects.impermanence
        ];

        persist.directories = [ "/var/lib/kept" ];

        nixos = {
          networking.hostName = "impb";
          disko.tests.extraChecks = btrfsScript;
          srvos.update-diff.enable = false;
        };
      };
    };

  hosts =
    (inputs.flake-parts.lib.evalFlakeModule { inherit inputs; } {
      imports = [
        modulesTree
        fixture
      ];
    }).config.den.hosts.x86_64-linux;

  nixosFor =
    host:
    inputs.nixpkgs.lib.nixosSystem {
      modules = [
        host.mainModule
        { nixpkgs.pkgs = pkgs; }
      ];
    };
in
{
  impermanence-zfs-rollback = (nixosFor hosts.imp).config.system.build.installTest;
  impermanence-btrfs-rollback = (nixosFor hosts.impb).config.system.build.installTest;
}
