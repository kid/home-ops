# System containerd for k3s (replaces k3s's embedded one), so the zfs
# snapshotter can be used — image layers become their own CoW datasets
# under modules/den/aspects/disko/zfs-disk-single.nix's local/containerd
# datasets, living outside the nix store where nix-collect-garbage can
# never reap them. k3s is pointed here via k3s.nix's
# --container-runtime-endpoint flag.
#
# NixOS's containerd module already defaults root/state/grpc.address to
# containerd's own built-in paths, and — since boot.zfs.enabled is true on
# zfs-disk-single hosts — already puts zfs on containerd's PATH and
# defaults the snapshotter to "zfs". The one default worth overriding is
# cni.bin_dir: the module points it at a static nix-store cni-plugins
# package (bridge/loopback/etc, no cilium-cni), but Cilium's own DaemonSet
# installs its CNI binary into /opt/cni/bin at runtime — containerd needs
# to look there instead to find it.
{
  den.aspects.k3s-containerd = {
    nixos = {
      systemd.services.k3s.requires = [ "containerd.service" ];

      virtualisation.containerd = {
        enable = true;
        settings.plugins."io.containerd.grpc.v1.cri".cni.bin_dir = "/opt/cni/bin";
      };
    };
  };
}
