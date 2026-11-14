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
    # Runs both prd k3s VMs on 4 cores: `power` pinned it at 1.2 GHz.
    settings.power-saving.cpuEpp = "balance_power";
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

  # The k3s VMs' bridges, named like the incus stack's networks
  # (tf-catalog/modules/incus-k3s). The Storage address sits on storage-prd.
  den.devices.node0.vmBridges = {
    k3s-prd = "K3s";
    storage-prd = "Storage";
  };

  den.aspects.node0.nixos =
    {
      pkgs,
      lib,
      nfs-exports ? [ ],
      k3s-nodes ? [ ],
      ...
    }:
    let
      # An export with a `writer` cluster (the nfs-exports quirk) is
      # read-write only for its nodes' Storage addresses and read-only for the
      # rest of the VLAN. Linux NFS picks a single host's entry over a
      # network's, whatever their order on the line.
      exportOf =
        e:
        let
          options = access: "(${access},insecure,no_subtree_check)";
          clients =
            if e ? writer then
              map (address: address + options "rw") (lib.concatMap storageAddresses (writersOf e))
              ++ [ (storageCidr + options "ro") ]
            else
              [ (storageCidr + options "rw") ];
        in
        "${e.path} ${builtins.concatStringsSep " " clients}\n";
      writersOf =
        e:
        k3s-nodes
        |> lib.filter (n: n.cluster == e.writer && n.address != null)
        |> map (n: n.hostname)
        |> lib.unique;
      storageAddresses =
        hostname:
        config.den.devices.${hostname}.interfaces
        |> lib.filter (i: i.network == "Storage")
        |> map (i: i.address);
      # Where syncoid keeps a copy of a snapshotted export: the same path on
      # tank, under tank/backups.
      backupOf = dataset: "tank/backups/${lib.removePrefix "zroot/" dataset}";
      snapshotted = lib.filter (e: e ? sanoid) nfs-exports;
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
          map (path: { inherit path; }) [
            "/tank/library"
            "/tank/library/animes"
            "/tank/library/movies"
            "/tank/library/series"
            "/tank/downloads/sabnzbd"
          ]
          ++ nfs-exports
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
      assertions =
        map (e: {
          assertion =
            lib.hasPrefix "zroot/clusters/" e.dataset
            && e.path == "/srv/${lib.removePrefix "zroot/" e.dataset}";
          message = "nfs-exports: ${e.dataset} must sit under zroot/clusters and be exported at its inherited mountpoint, not ${e.path}";
        }) nfs-exports
        ++ (
          nfs-exports
          |> lib.filter (e: e ? writer)
          |> map (e: {
            assertion =
              writersOf e != [ ] && lib.all (hostname: lib.length (storageAddresses hostname) == 1) (writersOf e);
            message = "nfs-exports: ${e.dataset} is writable by cluster ${e.writer}, which needs k3s nodes with exactly one Storage interface each in den.devices";
          })
        );
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
      # Snapshots only the exports that ask for them (their `sanoid` entry), so
      # autoSnapshot stays off for tank. sanoid's cache needs no persistence.
      services.sanoid = lib.mkIf (snapshotted != [ ]) {
        enable = true;
        datasets = snapshotted |> map (e: lib.nameValuePair e.dataset e.sanoid) |> lib.listToAttrs;
      };
      # Copies those snapshots to tank daily, off the NVMe pool: only sanoid's
      # (no sync snapshot of its own), and the copy keeps the same ones. The
      # copy is readonly and never mounted. Nothing here touches tank's own
      # properties: syncoid's zfs allow lands on tank/backups' datasets, which
      # it creates as needed. No state to persist: a local syncoid keeps none.
      services.syncoid = lib.mkIf (snapshotted != [ ]) {
        enable = true;
        interval = "*-*-* 06:00:00";
        commonArgs = [
          "--no-sync-snap"
          "--delete-target-snapshots"
        ];
        commands =
          snapshotted
          |> map (
            e:
            let
              target = backupOf e.dataset;
              # zfs receive creates no missing parent; tank/backups/clusters/...
              # down to the target's parent, none of them mounted.
              parents = lib.genList (
                i:
                target
                |> lib.splitString "/"
                |> lib.take (i + 2)
                |> lib.concatStringsSep "/"
              ) (lib.length (lib.splitString "/" target) - 2);
            in
            lib.nameValuePair e.dataset {
              inherit target;
              recvOptions = "u o readonly=on o canmount=noauto";
              # Without its own sync snapshots, syncoid only reads the source.
              localSourceAllow = [
                "hold"
                "send"
              ];
              localTargetAllow = [
                "create"
                "mount"
                "receive"
                "rollback"
                "destroy"
                "readonly"
                "canmount"
              ];
              service.serviceConfig.ExecStartPre = lib.mkBefore [
                "+${
                  pkgs.writeShellScript "syncoid-parents" (
                    parents
                    |> map (d: ''
                      /run/booted-system/sw/bin/zfs list ${d} >/dev/null 2>&1 \
                        || /run/booted-system/sw/bin/zfs create -o canmount=off ${d}
                    '')
                    |> lib.concatStrings
                  )
                }"
              ];
            }
          )
          |> lib.listToAttrs;
      };
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
