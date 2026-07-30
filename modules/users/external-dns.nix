# external-dns service account registry entry — no SSH keys, no NixOS host
# access, only RouterOS device membership.
{
  den.users.registry.external-dns.devices.rb5009.group = "external-dns";
  den.users.registry.external-dns.devices.crs320.group = "external-dns";
}
