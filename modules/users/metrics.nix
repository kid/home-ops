# metrics (mikrotik-exporter) service account registry entry — no SSH keys,
# no NixOS host access, only RouterOS device membership. TODO verify: ported
# as-is from the existing placeholder in modules/devices/{rb5009,crs320}.nix.
{
  den.users.registry.metrics.devices = {
    rb5009.group = "metrics";
    crs320.group = "metrics";
  };
}
