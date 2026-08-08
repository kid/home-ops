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
# defaults the CRI snapshotter to "zfs". Two defaults still need overriding:
#
# - cni.bin_dir: the module points it at a static nix-store cni-plugins
#   package (bridge/loopback/etc, no cilium-cni), but Cilium's own DaemonSet
#   installs its CNI binary into /opt/cni/bin at runtime — containerd needs
#   to look there instead to find it.
# - transfer.v1.local.unpack_config: the CRI snapshotter default doesn't
#   extend to the transfer plugin's unpacker, which only knows how to
#   unpack layers for snapshotters it has an explicit entry for (verified
#   against a real pull: `ctr images pull --snapshotter zfs` fails with
#   "no unpack platforms defined" without this).
{
  den.aspects.k3s-containerd = {
    # /var/lib/containerd is intentionally absent here: on zfs-disk-single
    # hosts it's its own dataset (see zfs-disk-single.nix), so it survives
    # wipeRootOnBoot untouched and a bind-mount here would shadow it.
    # /var/lib/cni is containerd's go-cni result/IPAM cache — generic to
    # whichever CNI plugin is in use, so it's kept regardless of Cilium vs.
    # anything else. (Not persisting podman/docker paths like kidibox's
    # containerd.nix does: home-ops runs neither.)
    persist.directories = [ "/var/lib/cni" ];

    nixos = {
      systemd.services.k3s.requires = [ "containerd.service" ];

      virtualisation.containerd = {
        enable = true;
        settings.plugins = {
          "io.containerd.grpc.v1.cri".cni.bin_dir = "/opt/cni/bin";
          "io.containerd.transfer.v1.local".unpack_config = [
            {
              platform = "linux/amd64";
              snapshotter = "zfs";
            }
          ];
        };
      };
    };
  };
}
