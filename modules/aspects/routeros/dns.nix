# DNS on a RouterOS device: the resolver and its static records, from the
# device's routerosInputs.dns (see modules/fleet/routeros/rb5009.nix).
{ lib, ... }:
let
  recordName = name: "dns_${lib.replaceStrings [ "." ] [ "_" ] name}";
in
{
  den.aspects.routeros.dns.tofu =
    { routerosDevice, ... }:
    let
      inherit (routerosDevice.aspect.routerosInputs.dns) inputs;
    in
    {
      resource.routeros_ip_dns.dns = {
        allow_remote_requests = true;
        servers = inputs.dns_upstream_servers;
        max_concurrent_queries = 200;
        max_concurrent_tcp_sessions = 40;
        cache_size = 1048576;
        cache_max_ttl = "1d";
      };

      resource.routeros_ip_dns_record = lib.mapAttrs' (
        name: record:
        lib.nameValuePair (recordName name) (
          {
            inherit name;
            inherit (record) address;
            type = record.type or "A";
            disabled = record.disabled or false;
          }
          // lib.optionalAttrs (record ? comment) { inherit (record) comment; }
        )
      ) inputs.dns_static_records;

      # From the catalog's ros-dns module, which the stack called until
      # these were ported. Drop once applied.
      moved = [
        {
          from = "module.dns.routeros_ip_dns.server";
          to = "routeros_ip_dns.dns";
        }
      ]
      ++ (
        inputs.dns_static_records
        |> lib.attrNames
        |> map (name: {
          from = ''module.dns.routeros_ip_dns_record.static["${name}"]'';
          to = "routeros_ip_dns_record.${recordName name}";
        })
      );
    };
}
