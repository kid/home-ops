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
    settings.disko.zfs-disk-single.settings.device_id =
      "/dev/disk/by-id/nvme-WD_BLACK_SN850X_1000GB_22518J459213";
  };

  den.devices.node0.interfaces = [
    {
      network = "Servers";
      hostNum = 10;
      mac = "74:56:3c:69:1e:30";
      # The trunk also carries the Storage VLAN.
      inherit (den.networks.Storage) mtu;
    }
    {
      network = "Storage";
      hostNum = 10;
      mac = "74:56:3c:69:1e:30";
      tagged = true;
    }
  ];

  den.aspects.node0.nixos = {
    imports = [ inputs.srvos.nixosModules.mixins-latest-zfs-kernel ];

    boot.loader.efi.canTouchEfiVariables = true;

    networking.hostId = "317406f6";

    networking.hostName = "node0";
    networking.useDHCP = false;

    i18n.defaultLocale = "en_US.UTF-8";

    # tank had no snapshot tasks under TrueNAS; srvos's default would
    # snapshot every tank dataset.
    services.zfs.autoSnapshot.enable = false;

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
        |> map (path: "${path} ${storageCidr}(rw,insecure,no_subtree_check)\n")
        |> builtins.concatStringsSep "";
    };
    # NFSv4 only; the kubelet negotiates 4.2.
    services.nfs.settings.nfsd.vers3 = false;
    networking.firewall.interfaces.storage.allowedTCPPorts = [ 2049 ];
  };

  # nfsd's client records (nfsdcld): without them, after a reboot the
  # NFSv4 clients can't reclaim their open state and locks in the grace period.
  den.aspects.node0.persist.directories = [ "/var/lib/nfs" ];

  den.aspects.node0.includes = [
    den.aspects.base
    den.aspects.disko.zfs-disk-single
    den.aspects.impermanence
    den.aspects.impermanence.tmpfs
    den.aspects.incus
    den.aspects.power-saving
  ];

  fleet.colmena.deployment.node0 = {
    targetHost = config.den.devices.node0.address;
    tags = [ "incus-host" ];
  };
}
