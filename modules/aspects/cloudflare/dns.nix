# Account-wide Cloudflare DNS records no environment owns. Included by the
# fleet (modules/fleet/fleet.nix) and rendered to tf-stacks/cloudflare.
{ config, ... }:
let
  # The kidibox.net zone (also den.clusters.prd.cloudflare.zoneId).
  zoneId = "dba2b63221015f1957d718defbf6b871";
  # rb5009's IP Cloud DDNS name, hand-copied from the rb5009 wireguard
  # stack's ip_cloud_dns_name output, like den.clusters.prd.cloudflare.tunnelId.
  rb5009DnsName = "hcy083ckp76.sn.mynetname.net";
  homeDomain = config.den.environments.prd.domain;
in
{
  den.aspects.cloudflare.dns."fleet-terragrunt-stacks" = {
    stack = "cloudflare";
    localModule = "cloudflare-dns";
    inputs = {
      zone_id = zoneId;
      records = {
        ${homeDomain} = {
          type = "CNAME";
          content = rb5009DnsName;
          comment = "rb5009 public address (MikroTik IP Cloud)";
        };
        "vpn.${homeDomain}" = {
          type = "CNAME";
          content = homeDomain;
          comment = "WireGuard endpoint on rb5009";
        };
      };
    };
  };
}
