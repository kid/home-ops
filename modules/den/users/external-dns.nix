# external-dns service account registry entry — no SSH keys, no NixOS host
# access, only RouterOS device membership.
{
  den.users.registry.external-dns.routerosDevices.rb5009.group = "external-dns";
  den.users.registry.external-dns.routerosDevices.crs320.group = "external-dns";
}
