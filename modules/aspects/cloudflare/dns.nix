# Account-wide Cloudflare DNS records no environment owns. Included by the
# fleet (modules/fleet/fleet.nix), so they're in its tofu stack (tf-stacks/fleet).
{ config, lib, ... }:
let
  # The kidibox.net zone (also den.clusters.prd.cloudflare.zoneId).
  zoneId = "dba2b63221015f1957d718defbf6b871";
  # rb5009's IP Cloud DDNS name, hand-copied from the rb5009 stack's
  # ip_cloud_dns_name output, like den.clusters.prd.cloudflare.tunnelId.
  rb5009DnsName = "hcy083ckp76.sn.mynetname.net";
  homeDomain = config.den.environments.prd.domain;

  records = {
    ${homeDomain} = {
      content = rb5009DnsName;
      comment = "rb5009 public address (MikroTik IP Cloud)";
    };
    "vpn.${homeDomain}" = {
      content = homeDomain;
      comment = "WireGuard endpoint on rb5009";
    };
  };
in
{
  den.aspects.cloudflare.dns.fleet-tofu.resource.cloudflare_dns_record = lib.mapAttrs' (
    name: record:
    lib.nameValuePair (lib.replaceStrings [ "." ] [ "_" ] name) {
      zone_id = zoneId;
      inherit name;
      inherit (record) content comment;
      type = "CNAME";
      proxied = false;
      ttl = 300;
    }
  ) records;
}
