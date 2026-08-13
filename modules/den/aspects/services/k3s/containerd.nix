# System containerd for k3s (replaces k3s's embedded one), so the zfs
# snapshotter can be used — image layers become their own CoW datasets
# under the local/containerd datasets declared below (via the `datasets`
# quirk, applied by disko-zfs), living outside the nix store where
# nix-collect-garbage can never reap them. k3s is pointed here via k3s.nix's
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
    # /var/lib/containerd is intentionally absent from persist.directories:
    # it's its own dataset (declared below via the `datasets` quirk, see
    # zfs-datasets-collector.nix), so it survives wipeRootOnBoot untouched
    # and a bind-mount here would shadow it.
    # /var/lib/cni is containerd's go-cni result/IPAM cache — generic to
    # whichever CNI plugin is in use, so it's kept regardless of Cilium vs.
    # anything else. (Not persisting podman/docker paths like kidibox's
    # containerd.nix does: home-ops runs neither.)
    persist.directories = [ "/var/lib/cni" ];

    # containerd's data root gets its own dataset, not nested under
    # local/root, so it survives wipeRootOnBoot untouched.
    datasets."zroot/local/containerd" = {
      mountpoint = "/var/lib/containerd";
      properties = {
        mountpoint = "legacy";
        atime = "off";
        recordsize = "128K";
      };
    };

    # The zfs snapshotter requires its root to BE a zfs dataset mountpoint
    # (not merely a directory on one), so it gets a dedicated child dataset
    # at exactly the plugin's path; each image layer becomes a CoW dataset
    # under it.
    datasets."zroot/local/containerd/snapshotter" = {
      mountpoint = "/var/lib/containerd/io.containerd.snapshotter.v1.zfs";
      properties = {
        mountpoint = "legacy";
        atime = "off";
        recordsize = "128K";
      };
    };

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
          # containerd's implicit default "runc" runtime entry carries its
          # own snapshotter (defaulting to "overlayfs") independently of the
          # top-level CRI snapshotter above. kubelet's image pulls go through
          # that per-runtime entry and silently pull with overlayfs unless
          # it's pinned here too — fails with "no unpack platforms defined"
          # since only a zfs unpack_config is declared. `ctr images pull
          # --snapshotter zfs` (this file's original verification) bypasses
          # the per-runtime lookup entirely, so it didn't catch this.
          "io.containerd.grpc.v1.cri".containerd.runtimes.runc = {
            runtime_type = "io.containerd.runc.v2";
            snapshotter = "zfs";
          };
        };
      };
    };
  };
}
