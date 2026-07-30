# external-dns service account registry entry — no SSH keys, no NixOS host
# access, only RouterOS device membership. TODO verify: ported as-is from
# the existing placeholder in modules/devices/rb5009.nix — crs320's own
# placeholder never had an external-dns group/user, only rb5009 did.
{
  den.users.registry.external-dns.devices.rb5009.group = "external-dns";
  den.users.registry.external-dns.devices.crs320.group = "external-dns";
}
