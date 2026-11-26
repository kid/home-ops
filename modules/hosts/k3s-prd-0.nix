# The prd cluster's only k3s server, on bare metal (the former node0), which
# also holds the data pool (tank) and serves NFS on the Storage VLAN.
# Installed with nixos-anywhere, updated with `colmena apply --on k3s-prd-0`.
{
  den,
  config,
  inputs,
  ...
}:
let
  storageCidr = config.den.environments.prd.networks.Storage.cidr;
  trustedCidr = config.den.environments.prd.networks.Trusted.cidr;
in
{
  den.hosts.x86_64-linux.k3s-prd-0 = {
    environment = "prd";
    system-access-groups = [ "admins" ];
    settings.disk.zfs.device = "/dev/disk/by-id/nvme-WD_BLACK_SN850X_1000GB_22518J459213";
    # Runs the whole prd cluster on 4 cores: `power` pinned it at 1.2 GHz.
    settings.power-saving.cpuEpp = "balance_power";
    settings.k3s.clusterName = "prd";
  };

  # One NIC: K3s native at the cluster's API address, Storage tagged.
  den.devices.k3s-prd-0.interfaces = [
    {
      network = "K3s";
      hostNum = 40;
      mac = "74:56:3c:69:1e:30";
      # The NIC's own MTU: a VLAN can't exceed its parent's, and the
      # tagged Storage VLAN is jumbo.
      inherit (den.networks.Storage) mtu;
    }
    {
      network = "Storage";
      hostNum = 40;
      mac = "74:56:3c:69:1e:30";
      tagged = true;
    }
  ];

  # NFS for the Storage VLAN (the exports below) and IPP for the Trusted one
  # (the printer below), through Cilium's host firewall
  # (modules/kubernetes/cilium/host-firewall.nix), which replaces the NixOS
  # one on a k3s node. NFSv4 only: nothing but 2049. Its own pods' mounts
  # come from this host itself and never reach the firewall.
  den.aspects.k3s-prd-0.firewall-ports =
    { host, ... }:
    [
      {
        port = 2049;
        protocol = "TCP";
        description = "NFS";
        fromCIDR = [ storageCidr ];
        cluster = host.settings.k3s.clusterName;
      }
      {
        port = 631;
        protocol = "TCP";
        description = "IPP";
        fromCIDR = [ trustedCidr ];
        cluster = host.settings.k3s.clusterName;
      }
    ];

  den.aspects.k3s-prd-0.nixos =
    {
      pkgs,
      lib,
      app-datasets ? [ ],
      k3s-nodes ? [ ],
      ...
    }:
    let
      # An export with a `writer` cluster (the app-datasets quirk) is
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
      # The app datasets k3s-prd-0 also exports over NFS (their `nfs`).
      exported = lib.filter (e: e.nfs or false) app-datasets;
      # Where syncoid keeps a copy of a snapshotted dataset: the same path on
      # tank, under tank/backups.
      backupOf = dataset: "tank/backups/${lib.removePrefix "zroot/" dataset}";
      snapshotted = lib.filter (e: e ? sanoid) app-datasets;
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
      # The iGPU's DMC, GuC and HuC blobs (linux-firmware). Mainline i915's
      # default on Alder Lake-S (enable_guc=2) loads HuC through GuC, which
      # the media engine needs for low-power encode; no kernel parameter.
      hardware.enableRedistributableFirmware = true;

      # No UART on this board (pikvm uses HDMI): srvos's ttyS0 console
      # leaves a serial getty failing and restarting every 10s.
      srvos.boot.consoles = [ "tty0" ];

      networking.hostId = "317406f6";

      networking.hostName = "k3s-prd-0";
      networking.useDHCP = false;

      i18n.defaultLocale = "en_US.UTF-8";

      # tank had no snapshot tasks under TrueNAS; srvos's default would
      # snapshot every tank dataset, and the containerd zfs snapshotter's
      # datasets must never carry snapshots of their own.
      services.zfs.autoSnapshot.enable = false;

      # home-ops' CI builds the workstation hosts on the in-cluster runner,
      # which this daemon doesn't trust: it may only add substituters listed
      # here, and their paths only verify against keys this daemon trusts. The
      # caches vulkan and fw13 substitute from beyond the base ones; keep in sync.
      nix.settings = {
        trusted-substituters = [
          "https://nix-community.cachix.org"
          "https://devenv.cachix.org"
          "https://nix-gaming.cachix.org"
          "https://nix-cache.tokidoki.dev/tokidoki"
          "https://umbriel.cachix.org"
          "https://noctalia.cachix.org"
          "https://cache.numtide.com"
        ];
        extra-trusted-public-keys = [
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
          "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
          "nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4="
          "tokidoki:MD4VWt3kK8Fmz3jkiGoNRJIW31/QAm7l1Dcgz2Xa4hk="
          "umbriel.cachix.org-1:JfNq/2yg2S6D6z4Z2dVSZrZlDPQTKtexB6GAVLD98nw="
          "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
          "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
        ];
      };

      # The ARC would otherwise grow to nearly all of the 31 GiB the pods
      # share: before the move the two VMs peaked at ~17 GiB used together
      # (guest kernels and k3s included), the pods' working sets at ~11 GiB,
      # so 8 GiB of ARC still leaves them room.
      boot.extraModprobeConfig = "options zfs zfs_arc_max=${toString (8 * 1024 * 1024 * 1024)}";

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
      # to destroy (it never runs destroys, but a later version might). Same
      # for the Incus VMs' datasets, kept as the rollback point until they
      # are destroyed by hand.
      disko.zfs.settings.ignoredDatasets = [
        "tank"
        "tank/*"
        "zroot/incus"
        "zroot/incus/*"
      ];

      # The Brother HL-2030 on USB, shared with the Trusted VLAN as
      # ipp://k3s-prd-0.k3s.home.kidibox.net/printers/HL-2030. mDNS doesn't
      # cross VLANs: clients add it by that URL (IPP Everywhere, the server
      # renders for brlaser). Stateless: the queue below is recreated on every
      # start, so nothing to persist; a reboot drops pending jobs. Started at
      # boot, not on the first connection: cups' postStart creates the queue,
      # and a socket-activated start answers that client before it exists.
      services.printing = {
        enable = true;
        startWhenNeeded = false;
        stateless = true;
        drivers = [ pkgs.brlaser ];
        # IPv4 only: on `*:631` (a dual-stack socket) IPv4 clients arrive as
        # ::ffff:a.b.c.d, which cupsd's IPv4 Allow rules never match (403).
        listenAddresses = [ "0.0.0.0:631" ];
        allowFrom = [
          "localhost"
          trustedCidr
        ];
        defaultShared = true;
        # cupsd answers 400 to a Host it doesn't know as its own: by
        # default only its hostname and addresses.
        extraConf = "ServerAlias k3s-prd-0.${den.networks.K3s.domain}";
      };
      hardware.printers = {
        ensureDefaultPrinter = "HL-2030";
        ensurePrinters = [
          {
            name = "HL-2030";
            deviceUri = "usb://Brother/HL-2030%20series?serial=H0J141728";
            model = "drv:///brlaser.drv/br2030.ppd";
            ppdOptions.PageSize = "A4";
          }
        ];
      };

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
          ++ exported
          |> map exportOf
          |> builtins.concatStringsSep "";
      };

      # The apps' own datasets (the app-datasets quirk), on the NVMe pool, not
      # tank, whose disks spin down. zroot/clusters sets the mountpoint and the
      # rest inherit it, so `zfs create` mounts each at its path; the levels
      # in between don't mount.
      disko.zfs.settings.datasets =
        let
          inherited = app-datasets |> lib.concatMap (e: ancestorsOf e.dataset) |> lib.unique;
        in
        lib.genAttrs inherited (_: {
          properties.canmount = "off";
        })
        // lib.optionalAttrs (app-datasets != [ ]) {
          "zroot/clusters".properties = {
            mountpoint = "/srv/clusters";
            canmount = "off";
          };
        }
        // (
          app-datasets
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
          message = "app-datasets: ${e.dataset} must sit under zroot/clusters and be mounted at its inherited mountpoint, not ${e.path}";
        }) app-datasets
        ++ (
          app-datasets
          |> lib.filter (e: e ? writer)
          |> map (e: {
            assertion =
              (e.nfs or false)
              && writersOf e != [ ]
              && lib.all (hostname: lib.length (storageAddresses hostname) == 1) (writersOf e);
            message = "app-datasets: ${e.dataset} is writable by cluster ${e.writer}, which needs `nfs = true` and k3s nodes with exactly one Storage interface each in den.devices";
          })
        );
      # Exported with root_squash: the apps run as root, so the server sees
      # nobody. At boot tmpfiles sets this once zfs-mount has run; on the
      # switch that creates a dataset, `zfs create` mounts it inside
      # disko-zfs, so disko-zfs sets it there too.
      systemd.tmpfiles.rules = map (e: "d ${e.path} 0750 nobody nogroup -") exported;
      systemd.services.disko-zfs.serviceConfig.ExecStartPost = lib.mkIf (exported != [ ]) (
        pkgs.writeShellScript "nfs-exports-owner" (
          exported
          |> map (e: ''
            if ${pkgs.util-linux}/bin/mountpoint -q ${e.path}; then
              chown nobody:nogroup ${e.path}
              chmod 0750 ${e.path}
            fi
          '')
          |> lib.concatStrings
        )
      );
      # Snapshots only the app datasets that ask for them (their `sanoid` entry), so
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
        # In the evening, when Plex usually has tank's disks spinning anyway.
        # The host runs on UTC; the timer follows local time across DST.
        interval = "*-*-* 21:00:00 Europe/Brussels";
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
    };

  # nfsd's client records (nfsdcld): without them, after a reboot the
  # NFSv4 clients can't reclaim their open state and locks in the grace period.
  den.aspects.k3s-prd-0.persist.directories = [ "/var/lib/nfs" ];

  den.aspects.k3s-prd-0.includes = [
    den.aspects.profiles.server
    den.aspects.disk.zfs
    den.aspects.impermanence
    den.aspects.power-saving
    den.aspects.k3s.server
    den.aspects.k3s.token
    den.aspects.k3s.cilium
    den.aspects.k3s.bootstrap
    den.aspects.k3s.external-secrets
    den.aspects.k3s.zfs-localpv-node
  ];

  fleet.colmena.deployment.k3s-prd-0 = {
    targetHost = config.den.devices.k3s-prd-0.address;
    # CI (the in-cluster runner) builds every PR's toplevel in this host's
    # store, so building here instead of locally is mostly a lookup.
    buildOnTarget = true;
  };
}
