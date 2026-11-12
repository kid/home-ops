{
  den,
  config,
  inputs,
  ...
}:
let
  storageCidr = config.den.environments.prd.networks.Storage.cidr;
in
{
  den.hosts.x86_64-linux.node0 = {
    environment = "prd";
    system-access-groups = [ "admins" ];
    settings.disk.zfs.device = "/dev/disk/by-id/nvme-WD_BLACK_SN850X_1000GB_22518J459213";
  };

  den.devices.node0.interfaces = [
    {
      network = "Servers";
      hostNum = 10;
      mac = "74:56:3c:69:1e:30";
      # The trunk also carries the Storage and K3s VLANs.
      inherit (den.networks.Storage) mtu;
    }
    {
      network = "Storage";
      hostNum = 10;
      mac = "74:56:3c:69:1e:30";
      tagged = true;
    }
  ];

  # The k3s VMs' bridges, named like node1's Incus networks: a VM moving here
  # attaches to the same bridge names. The Storage address sits on storage-prd.
  den.devices.node0.vmBridges = {
    k3s-prd = "K3s";
    storage-prd = "Storage";
  };

  den.aspects.node0.nixos =
    {
      pkgs,
      lib,
      nfs-exports ? [ ],
      ...
    }:
    let
      exportOf = path: "${path} ${storageCidr}(rw,insecure,no_subtree_check)\n";
      # A dataset's ancestors below zroot, down to its parent.
      ancestorsOf =
        dataset:
        let
          parts = lib.splitString "/" dataset;
        in
        lib.genList (i: parts |> lib.take (i + 2) |> lib.concatStringsSep "/") (lib.length parts - 2);
    in
    {
      imports = [ inputs.srvos.nixosModules.mixins-latest-zfs-kernel ];

      boot.loader.efi.canTouchEfiVariables = true;
      hardware.cpu.intel.updateMicrocode = true;

      # No UART on this board (pikvm uses HDMI): srvos's ttyS0 console
      # leaves a serial getty failing and restarting every 10s.
      srvos.boot.consoles = [ "tty0" ];

      networking.hostId = "317406f6";

      networking.hostName = "node0";
      networking.useDHCP = false;

      i18n.defaultLocale = "en_US.UTF-8";

      # tank had no snapshot tasks under TrueNAS; srvos's default would
      # snapshot every tank dataset.
      services.zfs.autoSnapshot.enable = false;

      # ZFS only. LVM would otherwise scan the Incus zvols and try to
      # activate the volume groups the k3s VMs created on them.
      services.lvm.enable = false;

      # The ARC would otherwise grow to nearly all RAM, which the k3s VMs need.
      boot.extraModprobeConfig = "options zfs zfs_arc_max=${toString (4 * 1024 * 1024 * 1024)}";

      services.udev.extraRules = ''
        # Spin the tank disks down after 30 minutes idle. On these Exos drives
        # (EPC) this arms the volatile Standby_z timer, so it's reapplied every boot.
        ACTION=="add", SUBSYSTEM=="block", ENV{DEVTYPE}=="disk", ATTR{queue/rotational}=="1", RUN+="${pkgs.hdparm}/bin/hdparm -S 241 /dev/%k"
        # r8169 clears L1 on the RTL8125 link at probe unless the firmware flags
        # ASPM safe (it doesn't here); it disables it again by itself on a Tx timeout.
        ACTION=="add|bind", SUBSYSTEM=="pci", DRIVER=="r8169", ATTR{link/l1_aspm}="1", ATTR{link/l1_1_aspm}="1", ATTR{link/l1_2_aspm}="1"
      '';

      # The data pool, moved from the TrueNAS VM. Never change its properties
      # or `zpool upgrade` it: TrueNAS 25.10 must still import it as the
      # rollback.
      boot.zfs.extraPools = [ "tank" ];

      # disko-zfs manages only zroot; it would list every tank dataset as one
      # to destroy (it never runs destroys, but a later version might).
      disko.zfs.settings.ignoredDatasets = [
        "tank"
        "tank/*"
      ];

      services.nfs.server = {
        enable = true;
        exports =
          [
            "/tank/library"
            "/tank/library/animes"
            "/tank/library/movies"
            "/tank/library/series"
            "/tank/downloads/sabnzbd"
          ]
          ++ map (e: e.path) nfs-exports
          |> map exportOf
          |> builtins.concatStringsSep "";
      };

      # The apps' own datasets (the nfs-exports quirk), on the NVMe pool, not
      # tank, whose disks spin down. zroot/clusters sets the mountpoint and the
      # rest inherit it, so `zfs create` mounts each at its export path; the
      # levels in between don't mount.
      disko.zfs.settings.datasets =
        let
          inherited = nfs-exports |> lib.concatMap (e: ancestorsOf e.dataset) |> lib.unique;
        in
        lib.genAttrs inherited (_: {
          properties.canmount = "off";
        })
        // lib.optionalAttrs (nfs-exports != [ ]) {
          "zroot/clusters".properties = {
            mountpoint = "/srv/clusters";
            canmount = "off";
          };
        }
        // (
          nfs-exports
          |> map (
            e:
            lib.nameValuePair e.dataset {
              properties = {
                atime = "off";
              }
              // e.properties or { };
            }
          )
          |> lib.listToAttrs
        );
      assertions = map (e: {
        assertion =
          lib.hasPrefix "zroot/clusters/" e.dataset
          && e.path == "/srv/${lib.removePrefix "zroot/" e.dataset}";
        message = "nfs-exports: ${e.dataset} must sit under zroot/clusters and be exported at its inherited mountpoint, not ${e.path}";
      }) nfs-exports;
      # Exported with root_squash: the apps run as root, so the server sees
      # nobody. At boot tmpfiles sets this once zfs-mount has run; on the
      # switch that creates a dataset, `zfs create` mounts it inside
      # disko-zfs, so disko-zfs sets it there too.
      systemd.tmpfiles.rules = map (e: "d ${e.path} 0750 nobody nogroup -") nfs-exports;
      systemd.services.disko-zfs.serviceConfig.ExecStartPost = lib.mkIf (nfs-exports != [ ]) (
        pkgs.writeShellScript "nfs-exports-owner" (
          nfs-exports
          |> map (e: ''
            if ${pkgs.util-linux}/bin/mountpoint -q ${e.path}; then
              chown nobody:nogroup ${e.path}
              chmod 0750 ${e.path}
            fi
          '')
          |> lib.concatStrings
        )
      );
      # NFSv4 only; the kubelet negotiates 4.2.
      services.nfs.settings.nfsd.vers3 = false;
      networking.firewall.interfaces.storage-prd.allowedTCPPorts = [ 2049 ];
    };

  # nfsd's client records (nfsdcld): without them, after a reboot the
  # NFSv4 clients can't reclaim their open state and locks in the grace period.
  den.aspects.node0.persist.directories = [ "/var/lib/nfs" ];

  den.aspects.node0.includes = [
    den.aspects.base
    den.aspects.disk.zfs
    den.aspects.impermanence
    den.aspects.incus
    den.aspects.i915-sriov.host
    den.aspects.power-saving
  ];

  fleet.colmena.deployment.node0 = {
    targetHost = config.den.devices.node0.address;
    tags = [ "incus-host" ];
  };
}
