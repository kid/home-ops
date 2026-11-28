# Account-wide Cloudflare DNS records no cluster owns, in the `cloudflare`
# tofu stack (modules/fleet/stacks/cloudflare.nix).
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

  resourceName = lib.replaceStrings [ "." ] [ "_" ];
in
{
  den.aspects.cloudflare.dns.tofu = {
    resource.cloudflare_dns_record = lib.mapAttrs' (
      name: record:
      lib.nameValuePair (resourceName name) {
        zone_id = zoneId;
        inherit name;
        inherit (record) content comment;
        type = "CNAME";
        proxied = false;
        ttl = 300;
      }
    ) records;

    # The stack keeps the Terragrunt unit's state (home-ops/cloudflare), whose
    # cloudflare-dns module keyed the records by name. Drop once applied.
    moved =
      records
      |> lib.attrNames
      |> map (name: {
        from = ''cloudflare_dns_record.this["${name}"]'';
        to = "cloudflare_dns_record.${resourceName name}";
      });
  };
}
