# Ships the node's journal (k3s, containerd, kernel, …) to its cluster's
# VLSingle, through the fixed-IP vlsingle-journald Service
# (kubernetes/victoria-metrics). Pod logs go through the OTel collector instead.
{ config, den, ... }:
{
  den.aspects.k3s.journald-upload = {
    # journal-upload's cursor (DynamicUser state), so a reboot resumes
    # instead of resending the whole journal.
    persist.directories = [ "/var/lib/private/systemd/journal-upload" ];

    nixos =
      { host, lib, ... }:
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
      };
  };
}
