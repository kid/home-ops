# Exports each SCSI/SATA rotational disk's ATA power mode as
# node_disk_ata_power_mode{device} through the in-cluster node-exporter's
# textfile collector (kubernetes/victoria-metrics), which reads this
# directory through its host-root mount. `smartctl -n standby` never wakes a
# drive. Values: 0 standby, 0x80-0x83 idle, 0xff active or idle.
{ config, den, ... }:
let
  dir = "/run/node-exporter";
in
{
  den.aspects.k3s.disk-power-mode.nixos =
    {
      host,
      lib,
      pkgs,
      ...
    }:
    let
      cluster = config.den.clusters.${host.settings.k3s.clusterName};
    in
    lib.mkIf (cluster.includesAspect den.aspects.kubernetes.victoria-metrics) {
      # Every node, disks or not: a missing directory is a scrape error.
      systemd.tmpfiles.rules = [ "d ${dir} 0755 root root -" ];

      systemd.services.disk-power-mode = {
        description = "Write the rotational disks' power mode for node-exporter";
        startAt = "minutely";
        path = [
          pkgs.jq
          pkgs.smartmontools
        ];
        serviceConfig.Type = "oneshot";
        # node-exporter must never read a half-written file: write, then rename.
        script = ''
          shopt -s nullglob
          out=${dir}/disk-power-mode.prom
          {
            echo '# HELP node_disk_ata_power_mode ATA power mode, read without waking the disk: 0 standby, 0x80-0x83 idle, 0xff active or idle.'
            echo '# TYPE node_disk_ata_power_mode gauge'
            for sys in /sys/block/sd*; do
              [ "$(cat "$sys/queue/rotational")" = 1 ] || continue
              dev=''${sys#/sys/block/}
              # Exit status 2 is "in standby", with power_mode still reported.
              { smartctl -n standby -j -i "/dev/$dev" || true; } \
                | jq -r --arg dev "$dev" \
                  '.power_mode.ata_value // empty | "node_disk_ata_power_mode{device=\"\($dev)\"} \(.)"'
            done
          } > "$out.tmp"
          mv "$out.tmp" "$out"
        '';
      };
    };
}
