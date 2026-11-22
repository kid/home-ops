# Ships the node's journal (k3s, containerd, kernel, …) to its cluster's
# VLSingle, through the fixed-IP vlsingle-journald Service
# (kubernetes/victoria-metrics). Pod logs go through the OTel collector instead.
{ config, den, ... }:
{
  den.aspects.k3s.journald-upload = {
    # journal-upload's cursor (DynamicUser state), so a reboot resumes where
    # it left off instead of skipping to the journal's end.
    persist.directories = [ "/var/lib/private/systemd/journal-upload" ];

    nixos =
      {
        host,
        lib,
        pkgs,
        ...
      }:
      let
        cluster = config.den.clusters.${host.settings.k3s.clusterName};
        address = cluster.networks.services.assignments.vlsingle-journald or null;
      in
      lib.mkIf (cluster.includesAspect den.aspects.kubernetes.victoria-metrics && address != null) {
        services.journald.upload = {
          enable = true;
          # journal-upload appends /upload.
          settings.Upload.URL = "http://${address}:9428/insert/journald";
        };

        # With no saved cursor, journal-upload sends the whole journal in one
        # go, which OOM-killed VLSingle. Start from the journal's end instead.
        systemd.services.systemd-journal-upload.serviceConfig.ExecStartPre =
          pkgs.writeShellScript "journal-upload-seed-cursor" ''
            state="$STATE_DIRECTORY/state"
            [ -e "$state" ] && exit 0
            cursor=$(${pkgs.systemd}/bin/journalctl -n 1 -o cat --show-cursor | ${pkgs.gnused}/bin/sed -n 's/^-- cursor: //p')
            [ -n "$cursor" ] && printf 'LAST_CURSOR=%s\n' "$cursor" > "$state"
            exit 0
          '';
      };
  };
}
